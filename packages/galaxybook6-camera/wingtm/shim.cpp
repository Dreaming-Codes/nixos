// libwingtm.so: LD_PRELOAD for the camera HAL process. Mirrors the live IntelCCA's init,
// statistics, AEC and AIQ calls to wingtm.exe (Windows CCA under Wine) and hands the Windows
// GBCE tone map to AIC through cca_pal_input_params.manual_gbce_setting, the HAL's own manual
// tonemap path. Everything else stays with the Linux CCA.
//
// WINGTM_CMD   shell command that starts wingtm.exe with stdin/stdout as the protocol pipe.
//              Unset: the shim passes every call through.
// Without a usable helper (spawn, init or I/O failure) the shim passes every call through.
#include <dlfcn.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <vector>

#include "IntelCCA.h"
#include "wingtm_proto.h"

extern char** environ;

static_assert(sizeof(cca::cca_aiq_params) == wingtm::kLinuxAiqParamsSize, "Linux cca_aiq_params layout");
static_assert(offsetof(cca::cca_aiq_params, pa_input) == wingtm::kLinuxAiqPaInput, "Linux pa_input offset");

namespace {

using InitFn = ia_err (*)(void*, const cca::cca_init_params*);
using DeinitFn = ia_err (*)(void*);
using StatsFn = ia_err (*)(void*, const cca::cca_stats_params*);
using AecFn = ia_err (*)(void*, uint64_t, const cca::cca_ae_input_params*, cca::cca_ae_results*);
using AiqFn = ia_err (*)(void*, uint64_t, const cca::cca_aiq_params*, cca::cca_aiq_results*);
using AicFn = ia_err (*)(void*, uint64_t, const cca::cca_pal_input_params*, cca::cca_multi_pal_output*, uint8_t,
                         int32_t);
using Aic2Fn = ia_err (*)(void*, uint64_t, const cca::cca_pal_input_params*, int32_t);
using QueryFn = cca::cca_frame_stats* (*)(void*, cca::cca_stats_buf_status, uint64_t);

template <typename F> F real(const char* sym) {
    void* p = dlsym(RTLD_NEXT, sym);
    // The HAL pulls libia_cca in through a dlopen'ed group that RTLD_NEXT does not search.
    if (!p) {
        if (void* h = dlopen("libia_cca-ipu75xa.so.0", RTLD_NOW | RTLD_NOLOAD)) p = dlsym(h, sym);
    }
    if (!p) fprintf(stderr, "wingtm: %s not found\n", sym);
    return reinterpret_cast<F>(p);
}

class Helper {
 public:
    bool start(const char* cmd) {
        int in[2], out[2];
        if (pipe(in) || pipe(out)) return false;
        posix_spawn_file_actions_t fa;
        posix_spawn_file_actions_init(&fa);
        posix_spawn_file_actions_adddup2(&fa, in[0], 0);
        posix_spawn_file_actions_adddup2(&fa, out[1], 1);
        posix_spawn_file_actions_addclose(&fa, in[1]);
        posix_spawn_file_actions_addclose(&fa, out[0]);
        const char* argv[] = {"/bin/sh", "-c", cmd, nullptr};
        std::vector<char*> env;
        for (char** e = environ; *e; e++)
            if (strncmp(*e, "LD_PRELOAD=", 11) != 0) env.push_back(*e);
        env.push_back(nullptr);
        const int rc = posix_spawn(&pid_, "/bin/sh", &fa, nullptr, const_cast<char**>(argv), env.data());
        posix_spawn_file_actions_destroy(&fa);
        close(in[0]);
        close(out[1]);
        to_ = in[1];
        from_ = out[0];
        signal(SIGPIPE, SIG_IGN);
        return rc == 0;
    }

    template <typename R>
    bool call(wingtm::Msg msg, uint64_t frameId, const void* a, size_t na, const void* b, size_t nb, R* reply) {
        std::lock_guard<std::mutex> l(io_);
        if (!alive()) return false;
        const wingtm::Header h = {msg, static_cast<uint32_t>(na + nb), frameId};
        if (!put(&h, sizeof(h)) || !put(a, na) || (nb && !put(b, nb)) || !get(reply, sizeof(R)) ||
            reply->magic != wingtm::kMagic) {
            fprintf(stderr, "wingtm: helper I/O failed, passing through\n");
            stop();
            return false;
        }
        return true;
    }

    bool alive() const { return to_ >= 0; }

    void stop() {
        if (to_ >= 0) close(to_);
        if (from_ >= 0) close(from_);
        to_ = from_ = -1;
        if (pid_ > 0) {
            kill(pid_, SIGTERM);
            waitpid(pid_, nullptr, 0);
            pid_ = -1;
        }
    }

 private:
    bool put(const void* p, size_t n) {
        const auto* b = static_cast<const uint8_t*>(p);
        while (n) {
            const ssize_t r = write(to_, b, n);
            if (r <= 0) return false;
            b += r;
            n -= static_cast<size_t>(r);
        }
        return true;
    }

    bool get(void* p, size_t n) {
        auto* b = static_cast<uint8_t*>(p);
        while (n) {
            const ssize_t r = read(from_, b, n);
            if (r <= 0) return false;
            b += r;
            n -= static_cast<size_t>(r);
        }
        return true;
    }

    std::mutex io_;
    pid_t pid_ = -1;
    int to_ = -1, from_ = -1;
};

struct State {
    Helper helper;
    void* cca = nullptr;  // the mirrored IntelCCA instance
    std::mutex gbceLock;
    bool haveGbce = false;
    cca::cca_gbce_params gbce;  // latest Linux GBCE result carrying the Windows tone map
};

State& state() {
    static State* s = new State;
    return *s;
}

bool mirrored(void* self) { return state().cca == self && state().helper.alive(); }

void injectToneMap(const cca::cca_pal_input_params* params) {
    State& s = state();
    auto* p = const_cast<cca::cca_pal_input_params*>(params);
    std::lock_guard<std::mutex> l(s.gbceLock);
    p->manual_gbce_setting = s.gbce;
    p->manual_gbce_setting.have_manual_settings = true;
}

// The HAL rewrites manual_gbce_setting only when it has manual settings, so a stale override
// would outlive the helper.
template <typename F> ia_err withToneMap(void* self, const cca::cca_pal_input_params* params, F run) {
    State& s = state();
    bool inject = false;
    if (mirrored(self) && !params->manual_gbce_setting.have_manual_settings) {
        std::lock_guard<std::mutex> l(s.gbceLock);
        inject = s.haveGbce;
    }
    if (!inject) return run();
    injectToneMap(params);
    const ia_err rc = run();
    const_cast<cca::cca_pal_input_params*>(params)->manual_gbce_setting.have_manual_settings = false;
    return rc;
}

}  // namespace

extern "C" {

ia_err _ZN3cca12IntelCCABase4initERKNS_15cca_init_paramsE(void* self, const cca::cca_init_params* p) {
    static InitFn fn = real<InitFn>("_ZN3cca12IntelCCABase4initERKNS_15cca_init_paramsE");
    const ia_err rc = fn(self, p);
    State& s = state();
    const char* cmd = getenv("WINGTM_CMD");
    if (rc != ia_err_none || !cmd || !*cmd) return rc;
    if (s.cca && s.cca != self) return rc;
    if (s.cca) {  // the HAL re-initialized the mirrored instance: start a fresh mirror
        s.helper.stop();
        s.cca = nullptr;
        std::lock_guard<std::mutex> l(s.gbceLock);
        s.haveGbce = false;
    }
    if (!s.helper.start(cmd)) {
        fprintf(stderr, "wingtm: cannot start helper\n");
        return rc;
    }
    wingtm::Reply r = {0, -1};
    if (!s.helper.call(wingtm::kInit, 0, p, sizeof(*p), nullptr, 0, &r) || r.rc != 0) {
        fprintf(stderr, "wingtm: helper init failed (%d), passing through\n", r.rc);
        s.helper.stop();
        return rc;
    }
    s.cca = self;
    fprintf(stderr, "wingtm: mirroring IntelCCA %p\n", self);
    return rc;
}

// The HAL tears its IntelCCA down when a camera session ends and builds a new one for the next,
// so drop the mirror here or every later session runs on the Linux tone map.
ia_err _ZN3cca12IntelCCABase6deinitEv(void* self) {
    static DeinitFn fn = real<DeinitFn>("_ZN3cca12IntelCCABase6deinitEv");
    State& s = state();
    if (s.cca == self) {
        s.helper.stop();
        s.cca = nullptr;
        std::lock_guard<std::mutex> l(s.gbceLock);
        s.haveGbce = false;
        fprintf(stderr, "wingtm: released IntelCCA %p\n", self);
    }
    return fn(self);
}

ia_err _ZN3cca12IntelCCABase14setStatsParamsERKNS_16cca_stats_paramsE(void* self, const cca::cca_stats_params* p) {
    static StatsFn fn = real<StatsFn>("_ZN3cca12IntelCCABase14setStatsParamsERKNS_16cca_stats_paramsE");
    static QueryFn query = real<QueryFn>("_ZN3cca8IntelCCA13queryStatsBufENS_20cca_stats_buf_statusEm");
    if (mirrored(self) && query) {
        const cca::cca_frame_stats* fs = query(self, cca::STATS_BUF_LATEST, cca::INVALID_FRAME_ID);
        wingtm::Reply r;
        if (fs && state().helper.call(wingtm::kStats, p->frame_id, p, sizeof(*p), fs, sizeof(*fs), &r) && r.rc)
            fprintf(stderr, "wingtm: helper statistics for frame %llu -> %d\n", static_cast<unsigned long long>(p->frame_id), r.rc);
    }
    return fn(self, p);
}

ia_err _ZN3cca12IntelCCABase6runAECEmRKNS_19cca_ae_input_paramsEPNS_14cca_ae_resultsE(
    void* self, uint64_t frameId, const cca::cca_ae_input_params* p, cca::cca_ae_results* results) {
    static AecFn fn = real<AecFn>("_ZN3cca12IntelCCABase6runAECEmRKNS_19cca_ae_input_paramsEPNS_14cca_ae_resultsE");
    const ia_err rc = fn(self, frameId, p, results);
    if (rc == ia_err_none && results && mirrored(self)) {
        wingtm::Reply r;
        if (state().helper.call(wingtm::kAec, frameId, p, sizeof(*p), results, sizeof(*results), &r) && r.rc)
            fprintf(stderr, "wingtm: helper AEC for frame %llu -> %d\n", static_cast<unsigned long long>(frameId), r.rc);
    }
    return rc;
}

ia_err _ZN3cca12IntelCCABase6runAIQEmRKNS_14cca_aiq_paramsEPNS_15cca_aiq_resultsE(
    void* self, uint64_t frameId, const cca::cca_aiq_params* p, cca::cca_aiq_results* results) {
    static AiqFn fn = real<AiqFn>("_ZN3cca12IntelCCABase6runAIQEmRKNS_14cca_aiq_paramsEPNS_15cca_aiq_resultsE");
    const ia_err rc = fn(self, frameId, p, results);
    if (rc != ia_err_none || !results || !mirrored(self) || !(p->bitmap & cca::CCA_MODULE_GBCE)) return rc;
    static wingtm::AiqReply* r = new wingtm::AiqReply;
    if (!state().helper.call(wingtm::kAiq, frameId, p, sizeof(*p), nullptr, 0, r) || r->rc != 0 ||
        r->toneMapSize == 0 || r->toneMapSize > cca::MAX_TONE_MAP_LUT_SIZE)
        return rc;
    cca::cca_gbce_params& g = results->gbce_output;
    memcpy(g.tone_map_lut, r->toneMap, sizeof(float) * r->toneMapSize);
    g.tone_map_lut_size = r->toneMapSize;
    State& s = state();
    std::lock_guard<std::mutex> l(s.gbceLock);
    s.gbce = g;
    s.haveGbce = true;
    return rc;
}

ia_err _ZN3cca8IntelCCA6runAICEmRKNS_20cca_pal_input_paramsERNS_20cca_multi_pal_outputEhi(
    void* self, uint64_t frameId, const cca::cca_pal_input_params* p, cca::cca_multi_pal_output* out, uint8_t bitmap,
    int32_t aicId) {
    static AicFn fn = real<AicFn>("_ZN3cca8IntelCCA6runAICEmRKNS_20cca_pal_input_paramsERNS_20cca_multi_pal_outputEhi");
    return withToneMap(self, p, [&] { return fn(self, frameId, p, out, bitmap, aicId); });
}

ia_err _ZN3cca8IntelCCA6runAICEmRKNS_20cca_pal_input_paramsEi(void* self, uint64_t frameId,
                                                              const cca::cca_pal_input_params* p, int32_t aicId) {
    static Aic2Fn fn = real<Aic2Fn>("_ZN3cca8IntelCCA6runAICEmRKNS_20cca_pal_input_paramsEi");
    return withToneMap(self, p, [&] { return fn(self, frameId, p, aicId); });
}

}  // extern "C"
