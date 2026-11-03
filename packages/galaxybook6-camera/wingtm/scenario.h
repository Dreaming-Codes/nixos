// One CCA run, shared by the Linux and the Windows (Wine) harness: init with an aiqb,
// configure the HAL's CBs, then per frame runAEC (manual exposure) -> runAIQ -> runAIC and
// dump the AIC outputs. `Api` adapts the IntelCCA methods of one CCA build.
#pragma once
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "aic_config.h"

struct Scenario {
    std::map<std::string, std::string> kv = {
        {"aiqb", ""}, {"cfg", ""}, {"out", "out"},
        {"frames", "4"}, {"exp_us", "66000"}, {"ag", "15.5"}, {"dg", "1.0"},
        {"awb_cct", "0"}, {"nr_level", "2"}, {"nr_strength", "0"}, {"ee_level", "2"}, {"ee_strength", "0"},
        {"stream", "60001"}, {"fps", "15"}, {"pac_sets", "2"}, {"opmode", "-1"}, {"decode_skip", "1"}, {"stats_level", "0"}, {"stats_rg", "0.64"}, {"stats_bg", "0.52"},
        {"lard_isp", "0"}, {"update_isp", "-1"}, {"init_bitmap", "0"}, {"manual_gbce", "0"}, {"tm_dir", ""}, {"reinit_isp", "-1"},
    };
    void parse(int argc, char** argv) {
        for (int i = 1; i < argc; i++) {
            const char* eq = strchr(argv[i], '=');
            if (!eq) continue;
            kv[std::string(argv[i], eq - argv[i])] = eq + 1;
        }
    }
    const std::string& s(const char* k) { return kv[k]; }
    double d(const char* k) { return atof(kv[k].c_str()); }
    int i(const char* k) { return atoi(kv[k].c_str()); }
};

static std::vector<uint8_t> readFile(const std::string& p) {
    std::vector<uint8_t> v;
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) return v;
    int c;
    while ((c = fgetc(f)) != EOF) v.push_back(static_cast<uint8_t>(c));
    fclose(f);
    return v;
}

// The HAL's per-CB configAIC + registerAICBuf (PAC sets and metadata buffers). Owns the buffers.
struct AicBuffers {
    std::vector<std::vector<aic::IaAicBuffer>> payloadDesc;
    std::vector<std::vector<size_t>> payloadSize;
    std::deque<std::vector<uint8_t>> buffers;
    std::deque<aic::IaAicBuffer> descs;
};

template <typename Api>
int configureCbs(Api& cca, AicConfig& cfg, int32_t stream, int sets, FILE* log, AicBuffers& ab) {
    int rc = 0;
    auto& payloadDesc = ab.payloadDesc;
    auto& payloadSize = ab.payloadSize;
    auto& buffers = ab.buffers;
    auto& descs = ab.descs;
    payloadDesc.assign(cfg.cbs.size(), {});
    payloadSize.assign(cfg.cbs.size(), {});
    for (size_t c = 0; c < cfg.cbs.size(); c++) {
        CbConfig& cb = cfg.cbs[c];
        cca::cca_aic_config conf;
        conf.cb_num = 1;
        conf.cb_config[0].group_id = cb.groupId;
        conf.cb_config[0].fragment_count = 0;
        conf.cb_config[0].kernel_group = &cb.group;
        std::unique_ptr<cca::cca_aic_kernel_offset> off(new cca::cca_aic_kernel_offset{});
        off->cb_num = 1;
        off->cb_kernel_offset[0].group_id = cb.groupId;
        off->cb_kernel_offset[0].num_kernels = cb.offsets.size();
        for (size_t k = 0; k < cb.offsets.size(); k++) off->cb_kernel_offset[0].kernels_offset[k] = cb.offsets[k];
        std::unique_ptr<cca::cca_aic_terminal_config> term(new cca::cca_aic_terminal_config{});
        payloadDesc[c].resize(cb.loads.size() + 1);
        term->cb_num = 1;
        term->cb_terminal_buf[0].group_id = cb.groupId;
        for (size_t t = 0; t < cb.loads.size(); t++) {
            term->cb_terminal_buf[0].terminal_buf[t].terminal_index = cb.loads[t].id;
            term->cb_terminal_buf[0].terminal_buf[t].payload = &payloadDesc[c][t];
        }
        term->cb_terminal_buf[0].num_terminal = cb.loads.size();
        rc = cca.configAIC(conf, *off, *term, stream, cfg.statsBufToTermIds.data());
        fprintf(log, "configAIC cb%zu group %d -> %d\n", c, cb.groupId, rc);
        fprintf(stderr, "configAIC cb%zu -> %d\n", c, rc);
        if (rc != 0) return rc;

        payloadSize[c].resize(cb.loads.size());
        for (size_t t = 0; t < cb.loads.size(); t++) {
            const auto& tb = term->cb_terminal_buf[0].terminal_buf[t];
            fprintf(log, "  terminal %u size %zu pacType %u meta %u\n", tb.terminal_index, tb.buf_size,
                    cb.loads[t].pacType, cb.loads[t].isMetadata);
            if (tb.buf_size && !cb.loads[t].isMetadata) payloadSize[c][t] = (tb.buf_size + 63) & ~size_t(63);
        }
        for (int set = 0; set < sets; set++) {
            std::unique_ptr<cca::cca_aic_terminal_config> reg(new cca::cca_aic_terminal_config{});
            reg->cb_num = 1;
            reg->cb_terminal_buf[0].group_id = cb.groupId;
            for (size_t t = 0; t < cb.loads.size(); t++) {
                if (!payloadSize[c][t]) continue;
                buffers.emplace_back(payloadSize[c][t], 0);
                descs.emplace_back();
                uint32_t n = reg->cb_terminal_buf[0].num_terminal++;
                auto& rb = reg->cb_terminal_buf[0].terminal_buf[n];
                rb.terminal_index = cb.loads[t].id;
                rb.buf_size = payloadSize[c][t];
                rb.payload = &descs.back();
                rb.payload->id = cb.loads[t].pacType;
                rb.payload->size = payloadSize[c][t];
                rb.payload->payloadPtr = buffers.back().data();
            }
            if (reg->cb_terminal_buf[0].num_terminal) {
                rc = cca.registerAICBuf(*reg, stream);
                fprintf(log, "registerAICBuf cb%zu set %d -> %d\n", c, set, rc);
            }
        }
        for (int set = 0; set < sets && !cb.metas.empty(); set++) {
            std::unique_ptr<cca::cca_aic_terminal_config> meta(new cca::cca_aic_terminal_config{});
            meta->cb_num = 1;
            meta->cb_terminal_buf[0].group_id = cb.groupId;
            for (size_t t = 0; t < cb.metas.size(); t++) {
                buffers.emplace_back(cb.metas[t].size, 0);
                descs.emplace_back();
                auto& rb = meta->cb_terminal_buf[0].terminal_buf[t];
                rb.terminal_index = cb.metas[t].id;
                rb.buf_size = cb.metas[t].size;
                rb.payload = &descs.back();
                rb.payload->id = cb.metas[t].pacType;
                rb.payload->size = cb.metas[t].size;
                rb.payload->payloadPtr = buffers.back().data();
                if (set == 0)
                    fprintf(log, "  metadata terminal %u size %u pacType %u\n", cb.metas[t].id, cb.metas[t].size,
                            cb.metas[t].pacType);
            }
            meta->cb_terminal_buf[0].num_terminal = cb.metas.size();
            rc = cca.registerAICBuf(*meta, stream);
            fprintf(log, "registerAICBuf(metadata) cb%zu set %d -> %d\n", c, set, rc);
        }
    }

    return 0;
}

