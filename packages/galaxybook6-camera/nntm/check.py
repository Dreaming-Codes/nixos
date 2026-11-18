"""Check the nntm element against reference.py on a small synthetic clip.

usage: check.py <datadir> <workdir>      (GST_PLUGIN_PATH must reach libgstnntm.so)

For both ranges: the element must equal the reference within one code value with the network
and with an identity grid, must change the picture with the network, must return its input
within one code value under the identity grid, and must return it untouched on bypass.
"""
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
    """Frames inside the RGB gamut: colour constant over each 2x2 block, luma varying per pixel."""
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


def element(workdir, name, src, props):
    out = f"{workdir}/{name}.nv12"
    caps = f"video/x-raw,format=NV12,width={W},height={H},framerate=30/1"
    subprocess.run(["gst-launch-1.0", "-q", "filesrc", f"location={src}", f"blocksize={W * H * 3 // 2}", "!", caps,
                    "!", "nntm", *props, "!", "filesink", f"location={out}"], check=True)
    return np.fromfile(out, np.uint8)


def worst(a, b):
    assert a.size == b.size == FRAMES * W * H * 3 // 2, (a.size, b.size)
    return int(np.abs(a.astype(int) - b).max())


def main():
    datadir, workdir = sys.argv[1:3]
    shading = reference.load_shading(f"{datadir}/shading.f32")
    checks = []
    for rng in ("limited", "full"):
        src = f"{workdir}/in-{rng}.nv12"
        frames = clip(rng == "limited")
        frames.tofile(src)
        props = [f"range={rng}", f"data-dir={datadir}"]
        for grid in ("network", "identity"):
            params = reference.Params(restricted=rng == "limited", shading=shading)
            ref = reference.Reference(datadir, params, grid == "identity")
            expect = np.concatenate([ref.frame(f, W, H) for f in frames.reshape(FRAMES, -1)])
            got = element(workdir, f"{grid}-{rng}", src, props + [f"identity-grid={grid == 'identity'}".lower()])
            checks.append((f"{rng} {grid}: element vs reference", worst(got, expect), 0, 1))
            checks.append((f"{rng} {grid}: element vs input", worst(got, frames), *((2, 255) if grid == "network" else (0, 1))))
        got = element(workdir, f"bypass-{rng}", src, props + ["bypass=true"])
        checks.append((f"{rng} bypass: element vs input", worst(got, frames), 0, 0))
    failed = False
    for name, value, lo, hi in checks:
        print(f"{name}: max difference {value} (allowed {lo}..{hi})")
        failed |= not lo <= value <= hi
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
