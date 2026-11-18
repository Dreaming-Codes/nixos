"""Slow reference for the nntm element: Samsung's Windows tone-mapping stage, operation by operation.

Every pixel operation is IEEE half precision in the order the Windows kernels perform it;
DERIVATION.md maps each function here to the kernel it mirrors.

usage: reference.py <datadir> <in.nv12> <out.nv12> <width> <height> [--range full|limited]
           [--strength S] [--radial R] [--identity-grid] [--frame-bytes N] [--frames N]
"""
import argparse
import struct
from dataclasses import dataclass, field

import numpy as np

H = np.float16
F = np.float32

GRID_Y, GRID_X, GRID_Z = 16, 16, 8
NET_SIZE = 256
FILTER_STRENGTH = 0.3


@dataclass
class Params:
    """Per-stream parameters as the Windows calculators hold them after scaling."""
    restricted: bool = True
    offset: tuple = (0, 128, 128)
    yuv2rgb: tuple = (8192, -2, 11218, 8192, -1334, -3336, 8192, 13220, -2)
    rgb2yuv: tuple = (3484, 11716, 1183, -2158, -7262, 9420, 9420, -8557, -863)
    gtm_a: int = 2
    gtm_b: int = 512
    gtm_c: int = 0
    guide_weight: int = 27955
    guide_bias: int = -12919
    strength: float = float(F(500) / F(1023))
    radial: float = float(F(540) / F(1023))
    shading: np.ndarray = field(default=None, repr=False)

    def yuv2rgb_h(self):
        m = np.array(self.yuv2rgb, F)
        return (m / m[0]).astype(H)

    def rgb2yuv_h(self):
        m = np.array(self.rgb2yuv, F)
        return (m / ((m[1] + m[0]) + m[2])).astype(H)

    def blend_map(self):
        """The parameter kernel's blend map, Q16, without a face region."""
        v = self.shading
        vmin = min(F(2), v.min())
        strength, radial = F(self.strength), F(self.radial)
        if vmin > F(1e-4):
            blend = ((F(1) / (v / vmin)) * radial + (F(1) - radial)) * strength
        else:
            blend = np.full_like(v, strength)
        return (blend * F(65536)).astype(np.int32)


def load_shading(path):
    data = open(path, "rb").read()
    w, h = struct.unpack_from("<II", data)
    return np.frombuffer(data, "<f4", w * h, 8).reshape(h, w)


def clamp(x, lo, hi):
    return np.minimum(np.maximum(x, H(lo)), H(hi))


def half_exp(x):
    return np.exp(x.astype(np.float64)).astype(H)


def cl_round(x):
    x = x.astype(np.float64)
    return (np.sign(x) * np.floor(np.abs(x) + 0.5)).astype(np.int32)


def to_rgb(y, u, v, p):
    """YUV code values (half arrays of one shape) to clamped RGB and their mean."""
    if p.restricted:
        y = clamp(y * H(1.1640625) + H(-18.625), 0, 255)
        u = clamp(u * H(1.142578125) + H(-18.28125), 0, 255)
        v = clamp(v * H(1.142578125) + H(-18.28125), 0, 255)
    inv255 = H(float.fromhex("0x1.01p-8"))
    un = (u - H(p.offset[1])) * inv255
    vn = (v - H(p.offset[2])) * inv255
    yn = (y - H(p.offset[0])) * inv255
    m = p.yuv2rgb_h()
    r = clamp(vn * m[2] + (un * m[1] + yn * m[0]), 0, 1)
    g = clamp(vn * m[5] + (un * m[4] + yn * m[3]), 0, 1)
    b = clamp(vn * m[8] + (un * m[7] + yn * m[6]), 0, 1)
    luma = (b + (g + r)) * H(float.fromhex("0x1.554p-2"))
    return r, g, b, luma


def planes(nv12, w, h):
    y = nv12[:w * h].reshape(h, w).astype(H)
    uv = nv12[w * h:w * h * 3 // 2].reshape(h // 2, w // 2, 2).astype(H)
    up = lambda c: np.repeat(np.repeat(c, 2, 0), 2, 1)
    return y, up(uv[..., 0]), up(uv[..., 1])


def resize_coeffs(in_size, out_size):
    scale = F(in_size) / F(out_size)
    support = max(F(1), scale)
    ksize = int(np.ceil(support)) * 2 + 1
    scale, support = H(scale), H(support)
    ss = H(1) / support
    bounds, coeffs = [], np.zeros((out_size, ksize), H)
    for xx in range(out_size):
        center = (H(xx) + H(0.5)) * scale
        xmin = min(max(int((center - support) + H(0.5)), 0), in_size)
        xmax = min(max(int((center + support) + H(0.5)), 0), in_size)
        n = xmax - xmin
        total, k = H(0), np.zeros(n, H)
        for i in range(n):
            t = abs(((H(i + xmin) - center) + H(0.5)) * ss)
            k[i] = H(1) - t if t < H(1) else H(0)
            total = total + k[i]
        if total != H(0):
            coeffs[xx, :n] = k / total
        bounds.append((xmin, n))
    return bounds, coeffs


def resize(img, out_w, out_h):
    """Pillow-style antialiased bilinear reduction, horizontal pass then vertical, in half precision."""
    in_h, in_w = img.shape
    bounds, coeffs = resize_coeffs(in_w, out_w)
    tmp = np.zeros((in_h, out_w), H)
    for xx, (xmin, n) in enumerate(bounds):
        acc = np.zeros(in_h, H)
        for i in range(n):
            acc = acc + coeffs[xx, i] * img[:, xmin + i]
        tmp[:, xx] = acc
    bounds, coeffs = resize_coeffs(in_h, out_h)
    out = np.zeros((out_h, out_w), H)
    for yy, (ymin, n) in enumerate(bounds):
        acc = np.zeros(out_w, H)
        for i in range(n):
            acc = acc + coeffs[yy, i] * tmp[ymin + i]
        out[yy] = acc
    return out


def temporal_filter(state, grid):
    """First grid passes through; later ones move the state 0.3 of the way."""
    if state is None:
        return grid.copy()
    alpha = H(F(FILTER_STRENGTH))
    return ((F(1) - F(alpha)) * state.astype(F) + (grid * alpha).astype(F)).astype(H)


def axis(scale, n, last):
    pos = H(scale) * np.arange(n).astype(H)
    lo = np.floor(pos)
    i0 = np.clip(lo.astype(np.int32), 0, last)
    i1 = np.clip((lo + H(1)).astype(np.int32), 0, last)
    return i0, i1, (lo + H(1)) - pos, pos - lo


def ltm_gain(luma, grid, p):
    """Slice the bilateral grid at every pixel and turn the mapped luma into a gain."""
    h, w = luma.shape
    g = grid.reshape(GRID_Y, GRID_X, GRID_Z, 2)
    y0, y1, wy0, wy1 = axis(F(15) / F(h - 1), h, GRID_Y - 1)
    x0, x1, wx0, wx1 = axis(F(15) / F(w - 1), w, GRID_X - 1)
    y0, y1, wy0, wy1 = y0[:, None], y1[:, None], wy0[:, None], wy1[:, None]
    x0, x1, wx0, wx1 = x0[None], x1[None], wx0[None], wx1[None]

    weight, bias = H(F(p.guide_weight) * F(1 / 8192)), H(F(p.guide_bias) * F(1 / 8192))
    z = H(7) / (half_exp(-(luma * weight + bias)) + H(1))
    lo = np.floor(z)
    z0 = np.clip(lo.astype(np.int32), 0, GRID_Z - 1)
    z1 = np.clip((lo + H(1)).astype(np.int32), 0, GRID_Z - 1)
    wz1, wz0 = z - lo, (lo + H(1)) - z

    # Half addition is not associative: the eight corners accumulate in this order.
    corners = [(wx0 * wy0, y0, x0), (wx1 * wy0, y0, x1), (wx0 * wy1, y1, x0), (wx1 * wy1, y1, x1)]
    coeff = []
    for c in range(2):
        acc = None
        for wxy, yi, xi in corners:
            for wz, zi in ((wz0, z0), (wz1, z1)):
                term = (wz * wxy) * g[yi, xi, zi, c]
                acc = term if acc is None else term + acc
        coeff.append(acc)
    mapped = clamp(coeff[1] + coeff[0] * luma, 0, 1)

    bmap = p.blend_map()
    bh, bw = bmap.shape
    m = (bmap.astype(F) * F(1 / 65536)).astype(H)
    by0, by1, wby0, wby1 = axis(F(bh - 1) / F(h - 1), h, bh - 1)
    bx0, bx1, wbx0, wbx1 = axis(F(bw - 1) / F(w - 1), w, bw - 1)
    by0, by1, wby0, wby1 = by0[:, None], by1[:, None], wby0[:, None], wby1[:, None]
    bx0, bx1, wbx0, wbx1 = bx0[None], bx1[None], wbx0[None], wbx1[None]
    blend = wbx0 * (wby0 * m[by0, bx0])
    blend = wbx1 * (wby0 * m[by0, bx1]) + blend
    blend = wbx0 * (wby1 * m[by1, bx0]) + blend
    blend = wbx1 * (wby1 * m[by1, bx1]) + blend

    out = clamp(luma + blend * (mapped - luma), 0, 1)
    with np.errstate(all="ignore"):
        return np.where(luma > H(0), out / luma, H(0))


def apply_gain(r, g, b, luma, gain, p):
    """Scale RGB by the gain; above 1, scale chroma by less so highlights keep their hue."""
    bp, c = H(F(p.gtm_b) / F(255)), H(F(p.gtm_c) / F(255))
    one = H(1)
    lg = gain * luma
    dr, dg, db = r - luma, g - luma, b - luma
    maxd = np.maximum(np.maximum(dr, db), dg)
    with np.errstate(all="ignore"):
        smax = np.where(maxd > H(0), (one - lg) / maxd, H(255))
        bp1 = bp + one
        num = np.maximum(bp1 - lg, H(0))
        inv = one / (bp1 - luma)
        power = np.full_like(luma, one)
        for _ in range(p.gtm_a):
            power = (num * power) * inv
        s = np.minimum(smax, ((c + gain) * power) / (c + one))
    grey = (r == g) & (r == b)
    out = []
    for ch, d in ((r, dr), (g, dg), (b, db)):
        boosted = np.where(grey, np.minimum(lg, one), lg + s * d)
        out.append(np.where(gain < one, np.minimum(gain * ch, one), boosted))
    return out


def postprocess(nv12, w, h, gain, p):
    y, u, v = planes(nv12, w, h)
    r, g, b, luma = to_rgb(y, u, v, p)
    r, g, b = apply_gain(r, g, b, luma, gain, p)
    m = p.rgb2yuv_h()
    yo = (m[2] * b + (m[1] * g + m[0] * r)) * H(255)
    uo = (m[5] * b + (m[4] * g + m[3] * r)) * H(255)
    vo = (m[8] * b + (m[7] * g + m[6] * r)) * H(255)

    def chroma(c, off):
        c = (c[1::2, 1::2] + (c[1::2, 0::2] + (c[0::2, 1::2] + c[0::2, 0::2]))) * H(0.25)
        return np.clip(cl_round(c) + off, 0, 255)

    yq = np.clip(cl_round(yo) + p.offset[0], 0, 255)
    uq, vq = chroma(uo, p.offset[1]), chroma(vo, p.offset[2])
    if p.restricted:
        def narrow(x, span, top):
            t = x * span + 128
            q = np.where(t & 255 == 0, (t >> 8) & 254, t >> 8)
            return np.clip(q + 16, 16, top)
        yq, uq, vq = narrow(yq, 220, 235), narrow(uq, 224, 240), narrow(vq, 224, 240)
    out = nv12.copy()
    out[:w * h] = yq.astype(np.uint8).ravel()
    out[w * h:w * h * 3 // 2] = np.stack([uq, vq], -1).astype(np.uint8).ravel()
    return out


class Reference:
    def __init__(self, datadir, params, identity_grid=False):
        self.p = params
        self.state = None
        self.net = None
        if not identity_grid:
            import openvino as ov
            core = ov.Core()
            model = core.read_model(f"{datadir}/nntm.xml", f"{datadir}/nntm.bin")
            self.net = core.compile_model(model, "CPU", {"INFERENCE_NUM_THREADS": 1}).create_infer_request()

    def grid(self, luma):
        if self.net is None:
            return np.tile(np.array([1, 0], H), GRID_Y * GRID_X * GRID_Z)
        small = resize(luma, NET_SIZE, NET_SIZE)
        self.net.infer({0: small.reshape(1, 1, NET_SIZE, NET_SIZE)})
        return self.net.get_output_tensor(0).data.astype(H).ravel().copy()

    def frame(self, nv12, w, h):
        y, u, v = planes(nv12, w, h)
        luma = to_rgb(y, u, v, self.p)[3]
        self.state = temporal_filter(self.state, self.grid(luma))
        return postprocess(nv12, w, h, ltm_gain(luma, self.state, self.p), self.p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("datadir"); ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("width", type=int); ap.add_argument("height", type=int)
    ap.add_argument("--range", choices=("full", "limited"), default="limited")
    ap.add_argument("--strength", type=float, default=Params.strength)
    ap.add_argument("--radial", type=float, default=Params.radial)
    ap.add_argument("--identity-grid", action="store_true")
    ap.add_argument("--frame-bytes", type=int)
    ap.add_argument("--frames", type=int)
    a = ap.parse_args()
    params = Params(restricted=a.range == "limited", strength=a.strength, radial=a.radial,
                    shading=load_shading(f"{a.datadir}/shading.f32"))
    ref = Reference(a.datadir, params, a.identity_grid)
    size = a.frame_bytes or a.width * a.height * 3 // 2
    with open(a.src, "rb") as src, open(a.dst, "wb") as dst:
        n = 0
        while a.frames is None or n < a.frames:
            buf = src.read(size)
            if len(buf) < size:
                break
            dst.write(ref.frame(np.frombuffer(buf, np.uint8), a.width, a.height).tobytes())
            n += 1


if __name__ == "__main__":
    main()
