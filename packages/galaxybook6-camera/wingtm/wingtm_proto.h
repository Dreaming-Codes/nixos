// Wire protocol between libwingtm.so (LD_PRELOAD in the HAL process) and wingtm.exe (Wine).
// Each request is a Header plus Linux-layout CCA structs; each gets a reply. Requests, in the
// order the HAL makes the calls: Init, then per frame Stats, Aec, Aiq.
#pragma once
#include <cstdint>

namespace wingtm {

enum Msg : uint32_t {
    kInit = 1,   // cca_init_params                          -> Reply
    kStats = 2,  // cca_stats_params, cca_frame_stats         -> Reply
    kAec = 3,    // cca_ae_input_params, cca_ae_results       -> Reply
    kAiq = 4,    // cca_aiq_params (Linux layout)             -> AiqReply
};

struct Header {
    uint32_t msg;
    uint32_t size;
    uint64_t frameId;
};

// Guards against anything else writing to the helper's stdout.
constexpr uint32_t kMagic = 0x4d544757;  // "WGTM"

struct Reply {
    uint32_t magic;
    int32_t rc;
};

constexpr uint32_t kToneMapMax = 2048;

struct AiqReply {
    uint32_t magic;
    int32_t rc;
    uint32_t toneMapSize;
    float toneMap[kToneMapMax];
};

// cca_aiq_params differs between the builds: the Windows cca_gbce_input_params ends with
// cphdr_mode, which moves pa_input, sa_input and dsd_input by 4 bytes.
constexpr uint32_t kLinuxAiqParamsSize = 0xb0;
constexpr uint32_t kLinuxAiqPaInput = 0x8c;
constexpr uint32_t kWinAiqPaInput = 0x90;

}  // namespace wingtm
