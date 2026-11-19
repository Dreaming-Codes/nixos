"""usage: check.py <datadir> <workdir> [cpu|gpu]      (GST_PLUGIN_PATH must reach libgstnntm.so, <workdir>/feed
must be feed.c built)

Without a GPU (the Nix build sandbox) the cpu back end is checked and `auto` must fall back to it."""
import struct
import subprocess
import sys

import numpy as np

import reference

W, H, FRAMES = 320, 192, 3
RGB2YUV = np.array(reference.Params.rgb2yuv, np.float64).reshape(3, 3) / 16383
TINTS = np.array([[0, 0, 0], [0.12, -0.04, -0.08], [-0.08, 0.1, -0.02], [-0.05, -0.05, 0.1]])


def noise(a, b, k):
    return ((a * 73856093 ^ b * 19349663 ^ k * 83492791) & 0xffff) / 65536


def clip(restricted):
    j, i = np.meshgrid(np.arange(W), np.arange(H))
    bj, bi = j // 2, i // 2
    frames = []
    for f in range(FRAMES):
        grey = 0.18 + 0.6 * ((bj * 2 + 6 * f) % W) / W * (0.4 + 0.6 * bi / (H // 2))
        rgb = grey[..., None] + TINTS[(bj // 20 + bi // 12) % 4] * noise(bj, bi, f)[..., None]
        rgb += 0.04 * (noise(j, i, f + 7) - 0.5)[..., None]
        assert 0 < rgb.min() and rgb.max() < 1
        yuv = rgb @ RGB2YUV.T * 255
        y, u, v = yuv[..., 0], yuv[0::2, 0::2, 1] + 128, yuv[0::2, 0::2, 2] + 128
        if restricted:
            y, u, v = 16 + y * 219 / 255, 128 + (u - 128) * 224 / 255, 128 + (v - 128) * 224 / 255
        frames.append(np.concatenate([np.round(y).ravel(), np.round(np.stack([u, v], -1)).ravel()]).astype(np.uint8))
    return np.concatenate(frames)


def record(p, uuid=reference.RECORD_UUID):
    """The PAL record the HAL would export for `p`; its guide fields hold zeros, which the stage must ignore."""
    body = bytearray(reference.KERNEL_SIZE)
    put = lambda at, values: struct.pack_into(f"<{len(values)}i", body, at, *values)
    put(0x8, p.offset)
    put(0x14, p.yuv2rgb)
    put(0x38, p.rgb2yuv)
    put(0x5c, (int(p.input_restricted), int(p.output_restricted)))
    put(0x64, p.blend.ravel().tolist())
    put(0x10064, (p.blend.shape[1], p.blend.shape[0], 0, 0, p.gtm_a, p.gtm_b, p.gtm_c))
    put(0x10080, [0x7fff] * 2049)
    size = reference.RECORD_HEADER + len(body) + 4
    return struct.pack("<6i", uuid, size, 257, 0, (1080 << 16) | 1920, 0) + bytes(body) + bytes(4)


def per_frame_params(shading, restricted):
    """Three frames that move every field the record carries: strength, blend map size, face cut, curve."""
    daylight = reference.Params.samsung(shading, restricted, strength=350 / 1023)
    ramp = np.add.outer(np.arange(7) * 4000, np.arange(9) * 2500) + 13000
    small = reference.Params(input_restricted=restricted, output_restricted=restricted, gtm_a=3, gtm_c=40,
                             blend=ramp.astype(np.int32))
    face = reference.Params.samsung(shading, restricted)
    face.blend[10:30, 20:40] = (face.blend[10:30, 20:40] * np.float32(1 - 306 / 1023)).astype(np.int32)
    return [daylight, small, face]


def element(workdir, name, src, props, records="-"):
    out = f"{workdir}/{name}.nv12"
    subprocess.run([f"{workdir}/feed", str(W), str(H), src, out, records, *props], check=True)
    return np.fromfile(out, np.uint8)


def worst(a, b):
    assert a.size == b.size == FRAMES * W * H * 3 // 2, (a.size, b.size)
    return int(np.abs(a.astype(int) - b).max())


def main():
    datadir, workdir = sys.argv[1:3]
    backend = sys.argv[3] if len(sys.argv) > 3 else "cpu"
    shading = reference.load_shading(f"{datadir}/shading.f32")
    checks = []
    for rng in ("limited", "full"):
        src = f"{workdir}/in-{rng}.nv12"
        frames = clip(rng == "limited")
        frames.tofile(src)
        props = [f"range={rng}", f"data-dir={datadir}", f"backend={backend}"]
        for grid in ("network", "identity"):
            params = reference.Params.samsung(shading, rng == "limited")
            ref = reference.Reference(datadir, grid == "identity")
            expect = np.concatenate([ref.frame(f, W, H, params) for f in frames.reshape(FRAMES, -1)])
            got = element(workdir, f"{grid}-{rng}", src, props + [f"identity-grid={grid == 'identity'}".lower()])
            checks.append((f"{rng} {grid}: element vs reference", worst(got, expect), 0, 1))
            checks.append((f"{rng} {grid}: element vs input", worst(got, frames), *((2, 255) if grid == "network" else (0, 1))))

        params = per_frame_params(shading, rng == "limited")
        records = f"{workdir}/records-{rng}.bin"
        open(records, "wb").write(b"".join(record(p) for p in params))
        ref = reference.Reference(datadir)
        expect = np.concatenate([ref.frame(f, W, H, p) for f, p in zip(frames.reshape(FRAMES, -1), params)])
        got = element(workdir, f"records-{rng}", src, props, records)
        checks.append((f"{rng} per-frame records: element vs reference", worst(got, expect), 0, 1))
        checks.append((f"{rng} per-frame records: element vs constants", worst(got, np.fromfile(f"{workdir}/network-{rng}.nv12", np.uint8)), 1, 255))
        foreign = f"{workdir}/foreign-{rng}.bin"
        open(foreign, "wb").write(b"".join(record(p, uuid=0) for p in params))
        got = element(workdir, f"foreign-{rng}", src, props, foreign)
        checks.append((f"{rng} records of another kernel: element vs constants", worst(got, np.fromfile(f"{workdir}/network-{rng}.nv12", np.uint8)), 0, 0))

        got = element(workdir, f"bypass-{rng}", src, props + ["bypass=true"])
        checks.append((f"{rng} bypass: element vs input", worst(got, frames), 0, 0))
        if backend == "cpu":
            auto = element(workdir, f"auto-{rng}", src, props[:2] + ["backend=auto"])
            checks.append((f"{rng} auto without a GPU: element vs cpu", worst(auto, np.fromfile(f"{workdir}/network-{rng}.nv12", np.uint8)), 0, 0))
    failed = False
    for name, value, lo, hi in checks:
        print(f"{name}: max difference {value} (allowed {lo}..{hi})")
        failed |= not lo <= value <= hi
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
