// cca::IntelCCA inside IntelDeviceMFT64.dll (Samsung/Intel IPU7 MFT with the statically linked CCA),
// called by RVA. RVAs are for the build of 2026-02-27 (CCA "ci_stable_ptl_ecg_20251207_1800_b20546-ptl_20260226_1800").
#pragma once
#include <windows.h>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "IntelCCA.h"

namespace rva {
const uintptr_t ctor = 0x124df0;            // cca::IntelCCA::IntelCCA()
const uintptr_t init = 0x121040;            // IntelCCABase::init(const cca_init_params&)
const uintptr_t reinitAic = 0x125450;       // IntelCCA::reinitAic(aicId)
const uintptr_t updateTuning = 0x124920;    // IntelCCABase::updateTuning(tag, lard&, nvm&, aicId)
const uintptr_t runAEC = 0x122740;          // IntelCCABase::runAEC
const uintptr_t runAIQ = 0x123490;          // IntelCCABase::runAIQ
const uintptr_t configAIC = 0x1250b0;       // IntelCCA::configAIC
const uintptr_t registerAICBuf = 0x1253f0;  // IntelCCA::registerAICBuf
const uintptr_t getAICBuf = 0x1251f0;       // IntelCCA::getAICBuf
const uintptr_t decodeStats = 0x125120;     // IntelCCA::decodeStats
const uintptr_t queryStatsBuf = 0x125310;   // IntelCCA::queryStatsBuf(status, frameId)
const uintptr_t setStatsParams = 0x124470;  // IntelCCABase::setStatsParams
const uintptr_t runAIC = 0x125580;          // IntelCCA::runAIC(frameId, params, multi_pal_output&, bitmap, aicId)
const uintptr_t version = 0x6002d8;         // imaging release string
const uintptr_t logEnv = 0xf18260;          // ia_env* used by the CCA/AIQ log function (0x11f5f0)
const uintptr_t logMask = 0xf18268;         // log level bits checked before logging
}  // namespace rva

struct WinCca {
    uint8_t* base;
    void* self;
    template <typename F> F fn(uintptr_t r) { return reinterpret_cast<F>(base + r); }

    const char* version() { return reinterpret_cast<const char*>(base + rva::version); }
    int init(const cca::cca_init_params& p) {
        return fn<int (*)(void*, const cca::cca_init_params*)>(rva::init)(self, &p);
    }
    int updateTuning(uint8_t tag, ia_lard_input_params& l, const cca::cca_nvm& n, int32_t aicId) {
        return fn<int (*)(void*, uint8_t, ia_lard_input_params*, const cca::cca_nvm*, int32_t)>(rva::updateTuning)(
            self, tag, &l, &n, aicId);
    }
    int reinitAic(int32_t aicId) { return fn<int (*)(void*, int32_t)>(rva::reinitAic)(self, aicId); }
    int configAIC(const cca::cca_aic_config& conf, const cca::cca_aic_kernel_offset& off,
                  cca::cca_aic_terminal_config& term, int32_t aicId, const int32_t* s2t) {
        return fn<int (*)(void*, const cca::cca_aic_config*, const cca::cca_aic_kernel_offset*,
                          cca::cca_aic_terminal_config*, int32_t, const int32_t*)>(rva::configAIC)(
            self, &conf, &off, &term, aicId, s2t);
    }
    int registerAICBuf(const cca::cca_aic_terminal_config& t, int32_t aicId) {
        return fn<int (*)(void*, const cca::cca_aic_terminal_config*, int32_t)>(rva::registerAICBuf)(self, &t, aicId);
    }
    int getAICBuf(cca::cca_aic_terminal_config& t, int32_t aicId) {
        return fn<int (*)(void*, cca::cca_aic_terminal_config*, int32_t)>(rva::getAICBuf)(self, &t, aicId);
    }
    int decodeStats(int32_t g, int64_t seq, int32_t aicId, bool skip) {
        return fn<int (*)(void*, int32_t, int64_t, int32_t, bool)>(rva::decodeStats)(self, g, seq, aicId, skip);
    }
    cca::cca_frame_stats* queryStatsBuf(cca::cca_stats_buf_status st, uint64_t id) {
        return fn<cca::cca_frame_stats* (*)(void*, cca::cca_stats_buf_status, uint64_t)>(rva::queryStatsBuf)(self, st, id);
    }
    int setStatsParams(const cca::cca_stats_params& p) {
        return fn<int (*)(void*, const cca::cca_stats_params*)>(rva::setStatsParams)(self, &p);
    }
    int runAEC(uint64_t id, const cca::cca_ae_input_params& p, cca::cca_ae_results* r) {
        return fn<int (*)(void*, uint64_t, const cca::cca_ae_input_params*, cca::cca_ae_results*)>(rva::runAEC)(
            self, id, &p, r);
    }
    int runAIQ(uint64_t id, const cca::cca_aiq_params& p, cca::cca_aiq_results* r) {
        return fn<int (*)(void*, uint64_t, const cca::cca_aiq_params*, cca::cca_aiq_results*)>(rva::runAIQ)(
            self, id, &p, r);
    }
    int runAIC(uint64_t id, const cca::cca_pal_input_params& p, cca::cca_multi_pal_output& o, uint8_t bm,
               int32_t aicId) {
        return fn<int (*)(void*, uint64_t, const cca::cca_pal_input_params*, cca::cca_multi_pal_output*, uint8_t,
                          int32_t)>(rva::runAIC)(self, id, &p, &o, bm, aicId);
    }
};

static void winccaLog(const char* fmt, va_list ap) {
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
}

// Loads the DLL, checks the build, installs the CCA log sink and constructs an IntelCCA.
static bool loadWinCca(WinCca& cca, const char* dll, int logMask) {
    static ia_env env = {winccaLog, winccaLog, winccaLog, winccaLog};
    HMODULE h = LoadLibraryA(dll);
    if (!h) return fprintf(stderr, "LoadLibrary %s failed %lu\n", dll, GetLastError()), false;
    cca.base = reinterpret_cast<uint8_t*>(h);
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(cca.base + reinterpret_cast<IMAGE_DOS_HEADER*>(h)->e_lfanew);
    if (nt->FileHeader.TimeDateStamp != 0x69a1d029 && !getenv("SKIP_STAMP_CHECK"))
        return fprintf(stderr, "unexpected DLL build %08lx\n", nt->FileHeader.TimeDateStamp), false;
    *reinterpret_cast<ia_env**>(cca.base + rva::logEnv) = &env;
    *reinterpret_cast<uint8_t*>(cca.base + rva::logMask) = static_cast<uint8_t>(logMask);
    cca.self = _aligned_malloc(0x10000, 64);
    memset(cca.self, 0, 0x10000);
    cca.fn<void* (*)(void*)>(rva::ctor)(cca.self);
    return true;
}
