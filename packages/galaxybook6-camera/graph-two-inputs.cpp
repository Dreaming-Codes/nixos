// Patch the Windows SC200PC graph settings in place so the Linux HAL runs their
// two-exposure graph 100032 (IsysDol -> LbffDol2Inputs -> BbpsWithTnr).
//
//   graph-two-inputs <hash-patched windows .bin> <out .bin>
//
// The file's data blocks are GraphConfiguration100032 structs of the HAL's
// autogen headers, so the settings stay as Samsung tuned them. What changes:
// - Both LBFF input feeders (ifd_pipe_1_3 55223, ifd_pipe_long_1_3 52982) are
//   set up on Windows for packed ISYS output, 25 pixels per 32 bytes. The
//   in-tree ISYS delivers unpacked 16-bit lines. In that layout a feeder hands
//   on half the scale its declared output depth says, and dol_lite expects
//   12-bit pixels (black level 256), so the feeders declare 13 bits.
// - The BBPS input and output records (25579, 20865) carry 0x2 in the third
//   byte of word 34 on Linux, and the BBPS 13 -> 5 self link streams, as in
//   Intel's Linux graphs.
// - The software nodes after BBPS (SwNntm, SwScaler) are dropped; BBPS feeds
//   the image sinks directly.
//
// Built against modules/ipu_desc/ipu75xa of the HAL plus kernel_meta.h from
// upstream's gen-kernel-meta.py.
#include "Ipu75xaStaticGraphReaderAutogen.h"
#include "kernel_meta.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <vector>

static constexpr uint32_t kIsysStride = ((1928 * 2) + 63) / 64 * 64;
static constexpr uint32_t kIsysHeight = 1088;
static constexpr uint8_t kFeederOutputBpp = 13;

template <class M> static int findKernel(uint16_t uuid) {
    for (uint32_t i = 0; i < M::count; i++)
        if (M::uuids[i] == uuid)
            return static_cast<int>(i);
    fprintf(stderr, "kernel %u is not in the node\n", uuid);
    exit(1);
}

template <class M> static uint8_t* kernelApi(uint8_t* api, uint16_t uuid) {
    uint32_t offset = 0;
    for (int k = findKernel<M>(uuid); k > 0; k--)
        offset += M::apiSizes[k - 1];
    return api + offset;
}

static void setWord(uint8_t* record, int word, uint32_t value) {
    memcpy(record + 2 + 4 * word, &value, 4);
}

static uint32_t getWord(const uint8_t* record, int word) {
    uint32_t v;
    memcpy(&v, record + 2 + 4 * word, 4);
    return v;
}

static void patchBlock(GraphConfiguration100032& g) {
    auto& sink = g.sinkMappingConfiguration;
    if (sink.preview == static_cast<uint8_t>(HwSink::ProcessedMainSink))
        sink.preview = static_cast<uint8_t>(HwSink::ImageMpSink);
    if (sink.video == static_cast<uint8_t>(HwSink::ProcessedSecondarySink))
        sink.video = static_cast<uint8_t>(HwSink::ImageDpSink);

    if (g.linkConfigurations[16].bufferSize == 0)
        g.linkConfigurations[16] = g.linkConfigurations[18];
    if (g.linkConfigurations[17].bufferSize == 0)
        g.linkConfigurations[17] = g.linkConfigurations[19];
    for (int k = 18; k <= 22; k++)
        g.linkConfigurations[k] = StaticGraphLinkConfiguration();

    auto& lb = g.lbffDol2InputsOuterNodeConfiguration;
    for (uint16_t uuid : {55223, 52982}) {
        uint8_t* ifd = kernelApi<LbffDol2InputsMeta>(lb.systemApiConfiguration, uuid);
        setWord(ifd, 11, (getWord(ifd, 11) & 0xffffU) | (kIsysStride << 16));
        setWord(ifd, 24, (getWord(ifd, 24) & 0xffffU) | (kIsysStride << 16));
        setWord(ifd, 15, 0xffff0101U);
        setWord(ifd, 18, 0x20000004U);
        setWord(ifd, 19, 0x00000101U);
        setWord(ifd, 36, 0x00010000U);
        lb.bppInfos[findKernel<LbffDol2InputsMeta>(uuid)].output_bpp = kFeederOutputBpp;
    }
    g.linkConfigurations[3].bufferSize = kIsysStride * kIsysHeight;
    g.linkConfigurations[4].bufferSize = kIsysStride * kIsysHeight;

    auto& bb = g.bbpsWithTnrOuterNodeConfiguration;
    for (uint16_t uuid : {25579, 20865}) {
        uint8_t* r = kernelApi<BbpsWithTnrMeta>(bb.systemApiConfiguration, uuid);
        setWord(r, 34, getWord(r, 34) | 0x00020000U);
    }
    g.linkConfigurations[13].streamingMode = 2;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <in.bin> <out.bin>\n", argv[0]);
        return 1;
    }

    FILE* f = fopen(argv[1], "rb");
    if (!f) {
        perror(argv[1]);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    std::vector<char> d(ftell(f));
    rewind(f);
    if (fread(d.data(), 1, d.size(), f) != d.size()) {
        perror(argv[1]);
        return 1;
    }
    fclose(f);

    char* p = d.data();
    BinaryHeader hdr;
    memcpy(&hdr, p, sizeof(hdr));
    p += sizeof(hdr);
    DataRangeHeader range;
    memcpy(&range, p, sizeof(range));
    p += sizeof(range);
    uint32_t nDesc = 0;
    for (int k = 0; k < enNumOfOutPins; k++)
        nDesc += range.NumberOfPinResolutions[k];
    p += sizeof(DriverDesc) * nDesc;
    uint32_t nGraphs;
    memcpy(&nGraphs, p, 4);
    p += 4 + nGraphs * sizeof(GraphHashCode);
    uint32_t nZoom;
    memcpy(&nZoom, p, 4);
    p += 4 + nZoom * sizeof(ZoomKeyResolution);
    const char* heads = p;
    p += sizeof(GraphConfigurationHeader) * hdr.numberOfResolutions;
    p += sizeof(SensorMode) * hdr.numberOfSensorModes;
    char* data = p;

    std::set<int32_t> done;
    for (uint32_t i = 0; i < hdr.numberOfResolutions; i++) {
        GraphConfigurationHeader h;
        memcpy(&h, heads + i * sizeof(h), sizeof(h));
        if (h.graphId != 100032 || !done.insert(h.resConfigDataOffset).second)
            continue;
        GraphConfiguration100032 g;
        memcpy(&g, data + h.resConfigDataOffset, sizeof(g));
        patchBlock(g);
        memcpy(data + h.resConfigDataOffset, &g, sizeof(g));
    }

    f = fopen(argv[2], "wb");
    if (!f || fwrite(d.data(), 1, d.size(), f) != d.size() || fclose(f) != 0) {
        perror(argv[2]);
        return 1;
    }
    printf("patched %zu blocks of graph 100032\n", done.size());
    return 0;
}
