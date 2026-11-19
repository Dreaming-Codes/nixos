#include "Ipu75xaStaticGraphReaderAutogen.h"
#include "kernel_meta.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <vector>

static constexpr uint32_t kIsysStride = ((1928 * 2) + 63) / 64 * 64;
static constexpr uint32_t kIsysHeight = 1088;
// On the unpacked 16-bit lines of the in-tree ISYS a feeder hands on half the scale its
// declared output depth says, and dol_lite expects 12-bit pixels (black level 256).
static constexpr uint8_t kFeederOutputBpp = 13;

static constexpr uint16_t kIfdPipe = 55223;
static constexpr uint16_t kIfdPipeLong = 52982;
static constexpr int kIfdStrideWords[] = {11, 24};
struct Word {
    int index;
    uint32_t value;
};
static constexpr Word kIfdUnpackedLineFormat[] = {
    {15, 0xffff0101U}, {18, 0x20000004U}, {19, 0x00000101U}, {36, 0x00010000U}};

static constexpr uint16_t kSlimTnrSpBcBifdYuv4nm1 = 25579;
static constexpr uint16_t kTnrScaleFpBodrYuv4n = 20865;
static constexpr int kIntelLinuxGraphFlagWord = 34;
static constexpr uint32_t kIntelLinuxGraphFlag = 0x00020000U;

static constexpr int kLinkIsysToLbffMain = 3;
static constexpr int kLinkIsysToLbffLong = 4;
static constexpr int kLinkTnrScaleFeedback = 13;
static constexpr int kLinkBbpsToImageMp = 16;
static constexpr int kLinkBbpsToImageDp = 17;
static constexpr int kLinkBbpsMpToSwNntm = 18;
static constexpr int kLinkBbpsDpToSwNntm = 19;
static constexpr int kLinkSwScalerToProcessedSecondary = 22;
static constexpr uint8_t kStreamingModeBclm = 2;

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

    if (g.linkConfigurations[kLinkBbpsToImageMp].bufferSize == 0)
        g.linkConfigurations[kLinkBbpsToImageMp] = g.linkConfigurations[kLinkBbpsMpToSwNntm];
    if (g.linkConfigurations[kLinkBbpsToImageDp].bufferSize == 0)
        g.linkConfigurations[kLinkBbpsToImageDp] = g.linkConfigurations[kLinkBbpsDpToSwNntm];
    for (int k = kLinkBbpsMpToSwNntm; k <= kLinkSwScalerToProcessedSecondary; k++)
        g.linkConfigurations[k] = StaticGraphLinkConfiguration();

    auto& lb = g.lbffDol2InputsOuterNodeConfiguration;
    for (uint16_t uuid : {kIfdPipe, kIfdPipeLong}) {
        uint8_t* ifd = kernelApi<LbffDol2InputsMeta>(lb.systemApiConfiguration, uuid);
        for (int word : kIfdStrideWords)
            setWord(ifd, word, (getWord(ifd, word) & 0xffffU) | (kIsysStride << 16));
        for (const Word& w : kIfdUnpackedLineFormat)
            setWord(ifd, w.index, w.value);
        lb.bppInfos[findKernel<LbffDol2InputsMeta>(uuid)].output_bpp = kFeederOutputBpp;
    }
    g.linkConfigurations[kLinkIsysToLbffMain].bufferSize = kIsysStride * kIsysHeight;
    g.linkConfigurations[kLinkIsysToLbffLong].bufferSize = kIsysStride * kIsysHeight;

    auto& bb = g.bbpsWithTnrOuterNodeConfiguration;
    for (uint16_t uuid : {kSlimTnrSpBcBifdYuv4nm1, kTnrScaleFpBodrYuv4n}) {
        uint8_t* r = kernelApi<BbpsWithTnrMeta>(bb.systemApiConfiguration, uuid);
        setWord(r, kIntelLinuxGraphFlagWord,
                getWord(r, kIntelLinuxGraphFlagWord) | kIntelLinuxGraphFlag);
    }
    g.linkConfigurations[kLinkTnrScaleFeedback].streamingMode = kStreamingModeBclm;
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
