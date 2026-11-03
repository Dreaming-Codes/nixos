// Loader for the .aiccfg produced by linux/aiccfg (format version 3): per CB the kernel
// group, kernel offsets and load terminals the HAL hands to IntelCCA::configAIC.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <stdexcept>
#include <string>
#include <vector>

#include "IntelCCA.h"

struct LoadTerminal {
    uint32_t id, pacType, isMetadata;
};

struct MetaTerminal {
    uint32_t id, pacType, size;
};

struct CbConfig {
    int32_t groupId;
    uint32_t resourceId;
    aic::ImagingKernelGroup group{};
    std::vector<aic::ia_pac_kernel_info> kernels;
    std::deque<std::vector<uint8_t>> storage;
    std::vector<cca::cca_kernel_offset> offsets;
    std::vector<LoadTerminal> loads;
    std::vector<MetaTerminal> metas;
};

struct AicConfig {
    std::vector<CbConfig> cbs;
    std::vector<int32_t> statsBufToTermIds;
};

class Reader {
 public:
    explicit Reader(const std::string& path) {
        FILE* f = fopen(path.c_str(), "rb");
        if (!f) throw std::runtime_error("open " + path);
        int c;
        while ((c = fgetc(f)) != EOF) d.push_back(static_cast<uint8_t>(c));
        fclose(f);
    }
    template <typename T> T get() {
        T v;
        bytes(&v, sizeof(T));
        return v;
    }
    void bytes(void* p, size_t n) {
        if (pos + n > d.size()) throw std::runtime_error("aiccfg truncated");
        memcpy(p, d.data() + pos, n);
        pos += n;
    }

 private:
    std::vector<uint8_t> d;
    size_t pos = 0;
};

template <typename T> static T* keep(CbConfig& cb, const void* src, size_t n) {
    cb.storage.emplace_back(n);
    memcpy(cb.storage.back().data(), src, n);
    return reinterpret_cast<T*>(cb.storage.back().data());
}

inline AicConfig loadAicConfig(const std::string& path) {
    Reader r(path);
    char magic[4];
    r.bytes(magic, 4);
    if (memcmp(magic, "AICC", 4) != 0 || r.get<uint32_t>() != 3) throw std::runtime_error("bad aiccfg");
    AicConfig cfg;
    cfg.cbs.resize(r.get<uint32_t>());
    for (auto& cb : cfg.cbs) {
        cb.groupId = r.get<int32_t>();
        cb.resourceId = r.get<uint32_t>();
        cb.group.operationMode = r.get<uint32_t>();
        cb.group.streamId = r.get<uint32_t>();
        cb.kernels.resize(r.get<uint32_t>());
        for (auto& k : cb.kernels) {
            ia_isp_bxt_run_kernels_t& rk = k.run_kernel;
            memset(&k, 0, sizeof(k));
            rk.stream_id = r.get<uint32_t>();
            rk.kernel_uuid = r.get<uint32_t>();
            rk.enable = r.get<int32_t>();
            r.bytes(rk.metadata, sizeof(rk.metadata));
            rk.bpp_info = r.get<ia_isp_bxt_bpp_info_t>();
            rk.output_count = r.get<uint32_t>();
            uint32_t nres = r.get<uint32_t>();
            if (nres) {
                std::vector<ia_isp_bxt_resolution_info_t> tmp(nres);
                r.bytes(tmp.data(), sizeof(tmp[0]) * nres);
                rk.resolution_info = keep<ia_isp_bxt_resolution_info_t>(cb, tmp.data(), sizeof(tmp[0]) * nres);
            }
            if (r.get<uint32_t>()) {
                auto h = r.get<ia_isp_bxt_resolution_info_t>();
                rk.resolution_history = keep<ia_isp_bxt_resolution_info_t>(cb, &h, sizeof(h));
            }
            rk.system_api.size = r.get<uint32_t>();
            if (rk.system_api.size) {
                std::vector<uint8_t> tmp(rk.system_api.size);
                r.bytes(tmp.data(), tmp.size());
                rk.system_api.data = keep<uint8_t>(cb, tmp.data(), tmp.size());
            }
            k.fragments_defined = r.get<uint32_t>() != 0;
        }
        cb.group.kernelCount = cb.kernels.size();
        cb.group.kernelList = cb.kernels.data();
        cb.offsets.resize(r.get<uint32_t>());
        for (auto& o : cb.offsets) {
            o.uuid = r.get<int32_t>();
            o.terminal_type = static_cast<aic::IaAicBufferTypes>(r.get<uint32_t>());
            o.terminal_index = r.get<uint32_t>();
            o.fragment = r.get<uint32_t>();
            o.num_offsets = r.get<uint32_t>();
            std::vector<uint32_t> tmp(o.num_offsets * 2);
            r.bytes(tmp.data(), 4 * tmp.size());
            o.offsets = keep<uint32_t>(cb, tmp.data(), 4 * o.num_offsets);
            o.sizes = keep<uint32_t>(cb, tmp.data() + o.num_offsets, 4 * o.num_offsets);
        }
        cb.loads.resize(r.get<uint32_t>());
        for (auto& l : cb.loads) {
            l.id = r.get<uint32_t>();
            l.pacType = r.get<uint32_t>();
            l.isMetadata = r.get<uint32_t>();
        }
        cb.metas.resize(r.get<uint32_t>());
        for (auto& m : cb.metas) {
            m.id = r.get<uint32_t>();
            m.pacType = r.get<uint32_t>();
            m.size = r.get<uint32_t>();
        }
    }
    cfg.statsBufToTermIds.resize(r.get<uint32_t>());
    r.bytes(cfg.statsBufToTermIds.data(), 4 * cfg.statsBufToTermIds.size());
    return cfg;
}
