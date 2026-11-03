// Builds the per-CB AIC configuration (kernel groups, kernel offsets, load terminals)
// that the Linux HAL passes to IntelCCA::configAIC, from the HAL's own static graph code,
// and serializes it for both harnesses (see ../harness/aic_config.h for the format).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <vector>

#include "Ipu75xaStaticGraphAutogen.h"
#include "Ipu75xaStaticGraphReaderAutogen.h"
#include "CBLayoutUtils.h"
#include "ia_pal_types_isp_ids_autogen.h"

using namespace icamera;

static FILE* out;
static void put(const void* p, size_t n) { fwrite(p, 1, n, out); }
template <typename T> static void put(const T& v) { put(&v, sizeof(T)); }

static const int kMaxSectionCount = 512;

static bool kernelExist(const StaticGraphNodeKernels& g, uint32_t uuid) {
    for (uint32_t i = 0; i < g.kernelCount; i++)
        if (g.kernelList[i].run_kernel.kernel_uuid == uuid) return true;
    return false;
}

struct KernelOffset {
    int32_t uuid;
    uint32_t terminal_type, terminal_index, fragment;
    std::vector<uint32_t> offsets, sizes;
};

// Mirrors CBStage::getKernelOffsetFromPayloadDesc.
static std::vector<KernelOffset> payloadOffsets(uint8_t resourceId, const StaticGraphNodeKernels& g) {
    const payload_descriptor_t** desc = nullptr;
    uint32_t count = 0;
    CBLayoutUtils::getCbPayloadDescriptor(resourceId, &desc, count);
    std::multimap<std::pair<uint8_t, uint32_t>, std::pair<uint32_t, uint32_t>> m;
    std::set<std::pair<uint8_t, uint32_t>> keys;
    for (uint32_t t = 0; t < count; t++) {
        if (!desc[t]) continue;
        for (uint32_t s = 0; s < desc[t]->number_of_sections; s++) {
            const cb_payload_descriptor_t& sec = desc[t]->sections[s];
            int uuid = CBLayoutUtils::cbDeviceId2Uuid(resourceId, sec.device_id);
            if (!kernelExist(g, uuid)) continue;
            auto k = std::make_pair(static_cast<uint8_t>(t), static_cast<uint32_t>(sec.device_id));
            m.insert({k, {sec.offset_in_payload, sec.payload_size}});
            keys.insert(k);
        }
    }
    std::vector<KernelOffset> res;
    for (auto& k : keys) {
        KernelOffset ko{};
        ko.uuid = CBLayoutUtils::cbDeviceId2Uuid(resourceId, k.second);
        ko.terminal_index = k.first;
        ko.terminal_type = CBLayoutUtils::getTerminalPacBufferType(resourceId, k.first);
        auto r = m.equal_range(k);
        for (auto it = r.first; it != r.second; ++it) {
            ko.offsets.push_back(it->second.first);
            ko.sizes.push_back(it->second.second);
        }
        res.push_back(ko);
    }
    return res;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <graph.IPU75XA.bin> <out.aiccfg> [width height]\n", argv[0]);
        return 2;
    }
    FILE* f = fopen(argv[1], "rb");
    if (!f) return perror(argv[1]), 1;
    fseek(f, 0, SEEK_END);
    StaticReaderBinaryData bin;
    bin.size = ftell(f);
    rewind(f);
    bin.data = malloc(bin.size);
    if (fread(bin.data, 1, bin.size, f) != bin.size) return 1;
    fclose(f);

    StaticGraphReader reader;
    if (reader.Init(bin) != StaticGraphStatus::SG_OK) return fprintf(stderr, "reader init failed\n"), 1;

    // GraphConfig::queryGraphSettings for one 1080p video stream (HAL built without DOL_FEATURE).
    GraphConfigurationKey key = {};
    key.fps = 30;
    key.attributes = getenv("AICCFG_ATTR") ? strtoul(getenv("AICCFG_ATTR"), nullptr, 0) : 0;
    key.preview.width = argc > 4 ? atoi(argv[3]) : 1920;
    key.preview.height = argc > 4 ? atoi(argv[4]) : 1080;
    key.preview.bpp = 8;
    IStaticGraphConfig* graph = nullptr;
    if (reader.GetStaticGraphConfig(key, &graph) != StaticGraphStatus::SG_OK)
        return fprintf(stderr, "no graph for key\n"), 1;
    int32_t graphId = -1, settingsId = -1;
    graph->getGraphId(&graphId);
    graph->getSettingsId(&settingsId);
    GraphTopology* topo = nullptr;
    graph->getGraphTopology(&topo);

    HwSink hSink = HwSink::Disconnected;
    VirtualSink vSink = VirtualSink::PreviewSink;
    graph->getVirtualSinkConnection(vSink, &hSink);
    SubGraphPublicInnerNodeConfiguration imageInner;
    imageInner.noMp = hSink != HwSink::ImageMpSink;
    imageInner.noDp = hSink != HwSink::ImageDpSink;
    SubGraphInnerNodeConfiguration inner;
    inner.imageInnerOptions = &imageInner;
    if (topo->configInnerNodes(inner) != StaticGraphStatus::SG_OK) fprintf(stderr, "configInnerNodes failed\n");
    fprintf(stderr, "graphId=%d settingsId=%d links=%d previewSink->hw %d\n", graphId, settingsId,
            topo->numOfLinks, static_cast<int>(hSink));

    // GraphConfig::saveOuterNode order: psys context id = index among non-ISYS dest nodes.
    std::vector<OuterNode*> nodes;
    for (int i = 0; i < topo->numOfLinks; i++) {
        GraphLink* l = topo->links[i];
        if (!l->isActive || !l->destNode || l->destNode->type == NodeTypes::Isys) continue;
        bool seen = false;
        for (auto* n : nodes) seen |= n == l->destNode;
        if (!seen) nodes.push_back(l->destNode);
    }

    out = fopen(argv[2], "wb");
    put("AICC", 4);
    put(static_cast<uint32_t>(3));
    put(static_cast<uint32_t>(nodes.size()));
    for (size_t ci = 0; ci < nodes.size(); ci++) {
        OuterNode* n = nodes[ci];
        const StaticGraphNodeKernels& g = n->nodeKernels;
        fprintf(stderr, "cb %zu: resource %u context %u kernels %u opmode %u stream %u fragments %u\n", ci,
                n->resourceId, n->contextId, g.kernelCount, g.operationMode, g.streamId,
                n->numberOfFragments);
        put(static_cast<int32_t>(ci));
        put(static_cast<uint32_t>(n->resourceId));
        put(g.operationMode);
        put(g.streamId);
        put(g.kernelCount);
        for (uint32_t k = 0; k < g.kernelCount; k++) {
            const ia_isp_bxt_run_kernels_t& rk = g.kernelList[k].run_kernel;
            put(rk.stream_id);
            put(rk.kernel_uuid);
            put(rk.enable);
            put(rk.metadata);
            put(rk.bpp_info);
            put(rk.output_count);
            uint32_t nres = rk.resolution_info ? (rk.output_count ? rk.output_count : 1) : 0;
            put(nres);
            if (nres) put(rk.resolution_info, sizeof(*rk.resolution_info) * nres);
            uint32_t hist = rk.resolution_history ? 1 : 0;
            put(hist);
            if (hist) put(*rk.resolution_history);
            put(rk.system_api.size);
            if (rk.system_api.size) put(rk.system_api.data, rk.system_api.size);
            uint32_t fd = g.kernelList[k].fragments_defined ? 1 : 0;
            put(fd);
        }
        // CBStage::allocMetadataBuffer: metadata terminals linked to this node.
        std::map<uint8_t, uint32_t> metaSize;
        for (int i = 0; i < topo->numOfLinks; i++) {
            GraphLink* l = topo->links[i];
            if (!l->isActive || l->type == LinkType::Node2Self) continue;
            if (l->srcNode ? l->srcNode->contextId != n->contextId
                           : (l->destNode && l->destNode->contextId != n->contextId))
                continue;
            uint8_t tid = l->srcNode ? l->srcTerminalId : l->destTerminalId;
            if (CBLayoutUtils::isMetaDataTerminal(n->resourceId, tid))
                metaSize[tid] = (l->linkConfiguration->bufferSize + 63) & ~63U;
        }
        auto offs = payloadOffsets(n->resourceId, g);
        // CBStage::getKernelOffsetFromTerminalDesc: spatial-in metadata terminals.
        {
            const TerminalDescriptor* td = nullptr;
            uint32_t tdCount = 0;
            CBLayoutUtils::getCbTerminalDescriptors(n->resourceId, td, tdCount);
            for (uint32_t i = 0; i < tdCount; i++) {
                const TerminalDescriptor& t = td[i];
                if (t.TerminalBufferType != TERMINAL_BUFFER_TYPE_METADATA ||
                    (t.TerminalType != TERMINAL_TYPE_CONNECT && t.TerminalDirection != TERMINAL_DIR_IN))
                    continue;
                if (t.PacBufferType != PAC_BUFFER_TYPE_SPATIAL_IN || !metaSize.count(t.TerminalId)) continue;
                KernelOffset ko{};
                if (strcmp(t.TerminalName, "TERMINAL_CONNECT_LSC_INPUT") == 0)
                    ko.uuid = ia_pal_uuid_isp_lsc_1_2;
                else if (strcmp(t.TerminalName, "TERMINAL_CONNECT_GMV_INPUT") == 0)
                    ko.uuid = ia_pal_uuid_isp_gmv_statistics_1_0;
                else
                    ko.uuid = t.TerminalLinkedKernel;
                ko.terminal_index = t.TerminalId;
                ko.terminal_type = CBLayoutUtils::getTerminalPacBufferType(n->resourceId, t.TerminalId);
                ko.offsets = {0};
                ko.sizes = {metaSize[t.TerminalId]};
                offs.push_back(ko);
            }
        }
        put(static_cast<uint32_t>(offs.size()));
        for (auto& o : offs) {
            put(o.uuid);
            put(o.terminal_type);
            put(o.terminal_index);
            put(o.fragment);
            put(static_cast<uint32_t>(o.offsets.size()));
            put(o.offsets.data(), 4 * o.offsets.size());
            put(o.sizes.data(), 4 * o.sizes.size());
        }
        const TerminalDescriptor* td = nullptr;
        uint32_t tdCount = 0;
        CBLayoutUtils::getCbTerminalDescriptors(n->resourceId, td, tdCount);
        std::vector<uint32_t> loads;
        for (uint32_t i = 0; i < tdCount; i++) {
            if (td[i].TerminalType != TERMINAL_TYPE_LOAD) continue;
            loads.push_back(td[i].TerminalId);
            loads.push_back(CBLayoutUtils::getTerminalPacBufferType(n->resourceId, td[i].TerminalId));
            loads.push_back(CBLayoutUtils::isMetaDataTerminal(n->resourceId, td[i].TerminalId));
        }
        put(static_cast<uint32_t>(loads.size() / 3));
        put(loads.data(), 4 * loads.size());
        put(static_cast<uint32_t>(metaSize.size()));
        for (auto& m : metaSize) {
            put(static_cast<uint32_t>(m.first));
            put(static_cast<uint32_t>(CBLayoutUtils::getTerminalPacBufferType(n->resourceId, m.first)));
            put(m.second);
        }
        fprintf(stderr, "   kernel offset entries %zu, load terminals %zu, metadata terminals %zu\n", offs.size(),
                loads.size() / 3, metaSize.size());
    }
    const int32_t* s2t = CBLayoutUtils::getStatsBufToTermIds();
    put(static_cast<uint32_t>(NUM_STATISTICS_BUFFER_TYPES));
    put(s2t, sizeof(int32_t) * NUM_STATISTICS_BUFFER_TYPES);
    fclose(out);
    return 0;
}
