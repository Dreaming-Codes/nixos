"""Extract what the nntm element needs from Samsung's Windows camera driver.

usage: extract.py <intelic_data.bin> <SC200PC_KAFC917_PTL.aiqb> <outdir>

Writes nntm.xml and nntm.bin (the tone-mapping network, OpenVINO IR), nntm.spv and resize.spv
(Samsung's SPIR-V pixel and resize kernels) and shading.f32
(u32 width, u32 height, then width*height float32: the normalised lens-shading gain
the Windows tone-mapping parameter kernel derives its blend map from).
"""
import struct
import sys

import numpy as np

MODEL_XML = "15056516632857880773"
MODEL_BIN = "10459174756635267373"
PIXEL_KERNELS = "5536108348999601368"
RESIZE_KERNELS = "18038158106866911913"
OUTPUTS = {MODEL_XML: "nntm.xml", MODEL_BIN: "nntm.bin", PIXEL_KERNELS: "nntm.spv", RESIZE_KERNELS: "resize.spv"}
LENS_SHADING_RECORD = 28
LIGHT_SOURCE_F11 = 19


def blobs(data):
    """Yield (key, bytes) for every blob of the INTL FlatBuffer."""
    u32 = lambda o: struct.unpack_from("<I", data, o)[0]
    i32 = lambda o: struct.unpack_from("<i", data, o)[0]
    u16 = lambda o: struct.unpack_from("<H", data, o)[0]
    field = lambda table, i: table + u16(table - i32(table) + 4 + 2 * i)
    def vector(o):
        o += u32(o)
        return o + 4, u32(o)
    def bytes_at(o):
        start, n = vector(o)
        return data[start:start + n]
    assert data[4:8] == b"INTL"
    root = u32(0)
    start, n = vector(field(root, 0))
    for i in range(n):
        table = start + 4 * i + u32(start + 4 * i)
        yield bytes_at(field(table, 0)).decode(), bytes_at(field(table, 1))


def cmc_record(aiqb, name_id):
    """Return the payload of one record of the aiqb's first (LCMC) section."""
    block = 0x18 + 16
    size = struct.unpack_from("<I", aiqb, block + 4)[0]
    o = block + 40
    while o + 8 <= block + size:
        rsize, _, name = struct.unpack_from("<IHH", aiqb, o)
        if name == name_id:
            return aiqb[o + 8:o + rsize]
        o += rsize
    raise SystemExit(f"aiqb has no record {name_id}")


def shading(aiqb):
    rec = cmc_record(aiqb, LENS_SHADING_RECORD)
    sources, channels, w, h = struct.unpack_from("<4H", rec, 16)
    assert channels == 4
    stride = 22 + w * h * channels * 2
    f32 = np.float32
    for i in range(sources):
        o = 24 + i * stride
        if struct.unpack_from("<I", rec, o)[0] != LIGHT_SOURCE_F11:
            continue
        p = np.frombuffer(rec, "<u2", w * h * channels, o + 22).reshape(channels, h, w).astype(f32)
        corner = np.maximum(np.maximum(p[:, 0, 0], p[:, 0, -1]), np.maximum(p[:, -1, 0], p[:, -1, -1]))
        q = p / corner[:, None, None]
        v = (((q[3] + q[0]) * f32(0.5) + q[1]) + q[2]) / f32(3)
        return w, h, v
    raise SystemExit("aiqb has no F11 lens-shading table")


def main():
    intelic, aiqb, out = sys.argv[1:4]
    found = dict((k, b) for k, b in blobs(open(intelic, "rb").read()) if k in OUTPUTS)
    for key, name in OUTPUTS.items():
        open(f"{out}/{name}", "wb").write(found[key])
    w, h, v = shading(open(aiqb, "rb").read())
    with open(f"{out}/shading.f32", "wb") as f:
        f.write(struct.pack("<II", w, h))
        f.write(v.astype("<f4").tobytes())


if __name__ == "__main__":
    main()
