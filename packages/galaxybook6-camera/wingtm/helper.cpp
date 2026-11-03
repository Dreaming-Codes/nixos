// wingtm.exe: Windows CCA (IntelDeviceMFT64.dll) as a Wine-hosted mirror of the Linux HAL's AIQ.
// It replays the HAL's init, statistics, AEC and AIQ calls (sent by libwingtm.so over
// stdin/stdout) on the Windows CCA and returns the Windows GBCE tone map for each AIQ run.
// AEC runs with manual exposure set to the Linux AEC result, so both CCAs see the same frames.
//
// usage: wine wingtm.exe dll=<IntelDeviceMFT64.dll> aiqb=<Windows aiqb> cfg=<.aiccfg> [stream=60014] [log_mask=1]
#include <fcntl.h>
#include <io.h>

#include <cstddef>

#include "scenario.h"
#include "wincca.h"
#include "wingtm_proto.h"

static_assert(sizeof(cca::cca_aiq_params) == 0xb8, "Windows cca_aiq_params layout");
static_assert(offsetof(cca::cca_aiq_params, pa_input) == wingtm::kWinAiqPaInput, "Windows pa_input offset");

static bool readAll(void* p, size_t n) {
    auto* b = static_cast<uint8_t*>(p);
    while (n) {
        const int r = _read(0, b, n > (1u << 30) ? (1u << 30) : static_cast<unsigned>(n));
        if (r <= 0) return false;
        b += r;
        n -= static_cast<size_t>(r);
    }
    return true;
}

static bool writeAll(const void* p, size_t n) {
    const auto* b = static_cast<const uint8_t*>(p);
    while (n) {
        const int r = _write(1, b, static_cast<unsigned>(n));
        if (r <= 0) return false;
        b += r;
        n -= static_cast<size_t>(r);
    }
    return true;
}

struct Mirror {
    WinCca cca;
    Scenario sc;
    AicConfig cfg;
    AicBuffers ab;
    int32_t stream = 60014;
    FILE* log = stderr;

    int init(const uint8_t* p, size_t n) {
        if (n != sizeof(cca::cca_init_params)) return -1;
        std::unique_ptr<cca::cca_init_params> init(new cca::cca_init_params);
        memcpy(init.get(), p, n);
        std::vector<uint8_t> aiqb = readFile(sc.s("aiqb"));
        if (aiqb.empty() || aiqb.size() > cca::MAX_CPF_LEN) return fprintf(log, "wingtm: bad aiqb\n"), -1;
        memcpy(init->aiq_cpf.buf, aiqb.data(), aiqb.size());
        init->aiq_cpf.size = aiqb.size();
        init->aic_stream_ids.count = 1;
        init->aic_stream_ids.ids[0] = stream;
        int rc = cca.init(*init);
        fprintf(log, "wingtm: init bitmap 0x%x -> %d\n", init->bitmap, rc);
        if (rc) return rc;
        // AIC is configured only so decodeStats provides the statistics buffers AIQ reads.
        for (auto& cb : cfg.cbs) {
            cb.group.streamId = stream;
            cb.group.operationMode = 0;
            for (auto& k : cb.kernels) k.run_kernel.stream_id = stream;
        }
        return configureCbs(cca, cfg, stream, 2, log, ab);
    }

    // decodeStats only hands out a statistics buffer for a frame AIC has run and been read back.
    void runAic(uint64_t frameId, uint64_t timestamp) {
        std::unique_ptr<cca::cca_pal_input_params> pal(new cca::cca_pal_input_params{});
        pal->stream_id = stream;
        pal->seq_id = static_cast<int64_t>(frameId);
        pal->timestamp = timestamp;
        pal->zoom_factor = 1.0F;
        pal->nr_setting = {ia_isp_feature_level_high, 0};
        pal->ee_setting = {ia_isp_feature_level_high, 0};
        pal->media_format = media_format_legacy;
        cca::cca_multi_pal_output out{};
        cca.runAIC(frameId, *pal, out, 0xff, stream);
        for (size_t c = 0; c < cfg.cbs.size(); c++) {
            std::unique_ptr<cca::cca_aic_terminal_config> q(new cca::cca_aic_terminal_config{});
            std::vector<aic::IaAicBuffer> got(cfg.cbs[c].loads.size());
            q->cb_num = 1;
            q->cb_terminal_buf[0].group_id = cfg.cbs[c].groupId;
            for (size_t t = 0; t < cfg.cbs[c].loads.size(); t++) {
                if (!ab.payloadSize[c][t]) continue;
                const uint32_t k = q->cb_terminal_buf[0].num_terminal++;
                q->cb_terminal_buf[0].terminal_buf[k].terminal_index = cfg.cbs[c].loads[t].id;
                q->cb_terminal_buf[0].terminal_buf[k].buf_size = ab.payloadSize[c][t];
                q->cb_terminal_buf[0].terminal_buf[k].payload = &got[k];
            }
            cca.getAICBuf(*q, stream);
        }
    }

    int stats(uint64_t frameId, const uint8_t* p, size_t n) {
        if (n != sizeof(cca::cca_stats_params) + sizeof(cca::cca_frame_stats)) return -1;
        const auto* linuxParams = reinterpret_cast<const cca::cca_stats_params*>(p);
        runAic(frameId, linuxParams->frame_timestamp);
        int rc = -1;
        for (const auto& cb : cfg.cbs)
            if ((rc = cca.decodeStats(cb.groupId, static_cast<int64_t>(frameId), stream, true)) == 0) break;
        if (rc) return rc;
        cca::cca_frame_stats* fs = cca.queryStatsBuf(cca::STATS_BUF_LATEST, cca::INVALID_FRAME_ID);
        if (!fs) return -2;
        memcpy(fs, p + sizeof(cca::cca_stats_params), sizeof(cca::cca_frame_stats));
        std::unique_ptr<cca::cca_stats_params> sp(new cca::cca_stats_params);
        memcpy(sp.get(), p, sizeof(cca::cca_stats_params));
        return cca.setStatsParams(*sp);
    }

    int aec(uint64_t frameId, const uint8_t* p, size_t n) {
        if (n != sizeof(cca::cca_ae_input_params) + sizeof(cca::cca_ae_results)) return -1;
        std::unique_ptr<cca::cca_ae_input_params> in(new cca::cca_ae_input_params);
        std::unique_ptr<cca::cca_ae_results> fromLinux(new cca::cca_ae_results);
        memcpy(in.get(), p, sizeof(*in));
        memcpy(fromLinux.get(), p + sizeof(*in), sizeof(*fromLinux));
        for (uint32_t e = 0; e < fromLinux->num_exposures && e < cca::MAX_NUM_EXPOSURE; e++) {
            const ia_aiq_exposure_parameters& x = fromLinux->exposures[e].exposure[0];
            in->manual_exposure_time_us[e] = x.exposure_time_us;
            in->manual_analog_gain[e] = x.analog_gain;
            in->manual_iso[e] = 0;
        }
        std::unique_ptr<cca::cca_ae_results> out(new cca::cca_ae_results{});
        return cca.runAEC(frameId, *in, out.get());
    }

    void aiq(uint64_t frameId, const uint8_t* p, size_t n, wingtm::AiqReply& r) {
        r.magic = wingtm::kMagic;
        r.rc = -1;
        r.toneMapSize = 0;
        if (n != wingtm::kLinuxAiqParamsSize) return;
        std::unique_ptr<cca::cca_aiq_params> in(new cca::cca_aiq_params{});
        auto* w = reinterpret_cast<uint8_t*>(in.get());
        memcpy(w, p, wingtm::kLinuxAiqPaInput);
        memcpy(w + wingtm::kWinAiqPaInput, p + wingtm::kLinuxAiqPaInput,
               wingtm::kLinuxAiqParamsSize - wingtm::kLinuxAiqPaInput);
        in->gbce_input.cphdr_mode = false;
        std::unique_ptr<cca::cca_aiq_results> out(new cca::cca_aiq_results{});
        r.rc = cca.runAIQ(frameId, *in, out.get());
        const cca::cca_gbce_params& g = out->gbce_output;
        r.toneMapSize = g.tone_map_lut_size <= wingtm::kToneMapMax ? g.tone_map_lut_size : 0;
        memcpy(r.toneMap, g.tone_map_lut, sizeof(float) * r.toneMapSize);
    }
};

int main(int argc, char** argv) {
    _setmode(0, _O_BINARY);
    _setmode(1, _O_BINARY);
    std::unique_ptr<Mirror> m(new Mirror);
    m->sc.kv["dll"] = "IntelDeviceMFT64.dll";
    m->sc.kv["log_mask"] = "0";
    m->sc.kv["stream"] = "60014";
    m->sc.parse(argc, argv);
    m->stream = m->sc.i("stream");
    if (!loadWinCca(m->cca, m->sc.s("dll").c_str(), m->sc.i("log_mask"))) return 1;
    m->cfg = loadAicConfig(m->sc.s("cfg"));
    fprintf(stderr, "wingtm: %s ready\n", m->cca.version());

    std::vector<uint8_t> buf;
    std::unique_ptr<wingtm::AiqReply> aiq(new wingtm::AiqReply);
    wingtm::Header h;
    while (readAll(&h, sizeof(h))) {
        buf.resize(h.size);
        if (!readAll(buf.data(), h.size)) break;
        if (h.msg == wingtm::kAiq) {
            m->aiq(h.frameId, buf.data(), h.size, *aiq);
            if (!writeAll(aiq.get(), sizeof(*aiq))) break;
            continue;
        }
        wingtm::Reply r = {wingtm::kMagic, -1};
        switch (h.msg) {
            case wingtm::kInit: r.rc = m->init(buf.data(), h.size); break;
            case wingtm::kStats: r.rc = m->stats(h.frameId, buf.data(), h.size); break;
            case wingtm::kAec: r.rc = m->aec(h.frameId, buf.data(), h.size); break;
        }
        if (!writeAll(&r, sizeof(r))) break;
    }
    return 0;
}
