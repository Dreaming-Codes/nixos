"""Render the neuralink Plymouth theme layers and the script data block.

Usage: generate.py <out-dir> <logic.script> <logo.svg> [limine-dir]
Writes PNG layers plus neuralink.script (data block + logic) into out-dir, and with
limine-dir the matching Limine wallpapers, one per LIMINE aspect.
"""

import math
import random
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

W, H = 2880, 1800
CX, CY = 1440, 470
WHITE = np.array([1.0, 1.0, 1.0])
ICE = np.array([0.62, 0.88, 1.0])
PATH_POINTS = 28

# N1 proportions, measured on the reference photo as fractions of the housing radius.
RH = 172
RING_R = 0.725 * RH
RING_W = 0.072 * RH
PUCK_R = RING_R + RING_W / 2 + 0.012 * RH
GAP = math.radians(15)
LED_A = math.radians(5.2)
LUG_D = 1.12 * RH
SQUIRCLE = 2.25
MARK_W = 0.95 * RH
EXIT_Y = CY + 0.98 * RH
BUNDLE_W = 0.62 * RH
BUNDLE_Y = CY + 2.3 * RH
STRANDS = 10

# Center-anchored rows use canvas y; HUD rows are distances from the canvas bottom.
LAYOUT = {
    "ref_w": W,
    "ref_h": H,
    "cx": CX,
    "cy": CY,
    "r": 1.12 * RH,
    "ring_r": RING_R,
    "gap": GAP,
    "led_a": LED_A,
    "wordmark_y": 968,
    "status_y": 1044,
    "secondary_y": 1108,
    "primary_y": 1166,
    "entry_y": 1240,
    "caps_y": 1302,
    "bullet_gap": 42,
    "label_gap": 34,
    "raster_w": 1800,
    "raster_rows": 14,
    "raster_gap": 7,
    "raster_bottom": 268,
    "progress_bottom": 104,
    "progress_segments": 120,
}
RASTER_H = LAYOUT["raster_rows"] * LAYOUT["raster_gap"]

TEXT_BOX = (CX - 560, 910, CX + 560, 1340)
HUD_TOP = 1440

# Limine wallpapers: symmetric vertical crops of the reference canvas, so the menu stays centered.
LIMINE = {"16x10": (W, H), "16x9": (W, 1620)}
MENU_BOX = (CX - 620, 690, CX + 620, 1120)
BRANDING_BOX = (CX - 440, 0, CX + 440, 190)
LIMINE_WORDMARK_Y = 1485


def gaussian_blur(a, sigma):
    pad = int(3 * sigma) + 2
    p = np.pad(a, pad)
    fy = np.fft.fftfreq(p.shape[0])[:, None]
    fx = np.fft.rfftfreq(p.shape[1])[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fx**2 + fy**2))
    out = np.fft.irfft2(np.fft.rfft2(p) * g, s=p.shape)
    return np.clip(out[pad:-pad, pad:-pad], 0, None)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


class Ink:
    """Supersampled single-channel line art, read back as float intensity."""

    def __init__(self, w, h, ss=3):
        self.w, self.h, self.ss = w, h, ss
        self.img = Image.new("L", (w * ss, h * ss), 0)
        self.draw = ImageDraw.Draw(self.img)

    def _p(self, pts):
        return [(x * self.ss, y * self.ss) for x, y in pts]

    def line(self, pts, value, width=1.0):
        wpx = max(1, round(width * self.ss))
        self.draw.line(self._p(pts), fill=int(255 * min(1, value)), width=wpx, joint="curve")
        if wpx > 2:
            for x, y in (pts[0], pts[-1]):
                self.dot(x, y, width / 2, value)

    def dot(self, x, y, r, value):
        s = self.ss
        self.draw.ellipse(
            (x * s - r * s, y * s - r * s, x * s + r * s, y * s + r * s),
            fill=int(255 * min(1, value)),
        )

    def array(self):
        small = self.img.resize((self.w, self.h), Image.BOX)
        return np.asarray(small, dtype=np.float64) / 255.0


def save_rgba(path, rgb, alpha):
    alpha = np.clip(alpha, 0, 1)
    rgb = np.clip(rgb, 0, 1)
    data = np.dstack([rgb, alpha[..., None]])
    Image.fromarray((data * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)


def tinted(intensity, core):
    """Glow tint: bright cores read white, falloff reads ice cyan."""
    w = np.clip(core * 1.6, 0, 1)[..., None]
    return ICE * (1 - w) + WHITE * w


def svg_alpha(svg, width, element=None, ss=4):
    """Coverage of the SVG (or one element of it) rendered `width` px wide."""
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "out.png"
        cmd = ["rsvg-convert", "-w", str(width * ss), "-o", str(png), str(svg)]
        if element:
            cmd[1:1] = ["-i", element]
        subprocess.run(cmd, check=True)
        img = Image.open(png).getchannel("A")
    h = max(1, round(img.height / ss))
    return np.asarray(img.resize((width, h), Image.BOX), dtype=np.float64) / 255.0


def pad_to(a, w, h):
    out = np.zeros((h, w))
    y, x = (h - a.shape[0]) // 2, (w - a.shape[1]) // 2
    out[y:y + a.shape[0], x:x + a.shape[1]] = a
    return out


def bezier(p0, p1, p2, p3, n):
    t = np.linspace(0, 1, n)[:, None]
    return (
        (1 - t) ** 3 * p0
        + 3 * (1 - t) ** 2 * t * p1
        + 3 * (1 - t) * t**2 * p2
        + t**3 * p3
    )


def resample(pts, n):
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    at = np.linspace(0, cum[-1], n)
    return np.stack([np.interp(at, cum, pts[:, 0]), np.interp(at, cum, pts[:, 1])], 1), cum[-1]


def box_distance(xx, yy, box):
    x0, y0, x1, y1 = box
    bx = np.maximum(np.maximum(x0 - xx, xx - x1), 0)
    by = np.maximum(np.maximum(y0 - yy, yy - y1), 0)
    return np.hypot(bx, by)


def in_text_box(x, y, margin=0):
    x0, y0, x1, y1 = TEXT_BOX
    return x0 - margin < x < x1 + margin and y0 - margin < y < y1 + margin


def in_device(x, y, margin=0):
    if math.hypot(x - CX, y - CY) < 1.3 * RH + 110 + margin:
        return True
    return abs(x - CX) < BUNDLE_W + 90 + margin and CY < y < BUNDLE_Y + 70 + margin


def place_neurons(rng):
    nodes = []
    for _ in range(400000):
        if len(nodes) >= 250:
            break
        x, y = rng.uniform(70, W - 70), rng.uniform(60, HUD_TOP - 30)
        d = math.hypot(x - CX, y - BUNDLE_Y)
        if in_device(x, y) or in_text_box(x, y):
            continue
        if rng.random() > min(1.0, max(0.12, 1.3 - d / 1350)):
            continue
        if any((x - a) ** 2 + (y - b) ** 2 < 62**2 for a, b in nodes):
            continue
        nodes.append((x, y))
    return nodes


def fan_angle(x, y):
    """Turn away from straight down at the bundle foot; negative is left."""
    return math.degrees(math.atan2(x - CX, y - BUNDLE_Y))


def reachable(x, y):
    dx = abs(x - CX)
    if y > TEXT_BOX[1] - 20:
        return dx > TEXT_BOX[2] - CX + 140 and y < HUD_TOP - 90
    return dx > 1.3 * RH + 200 and y > 170


def choose_endpoints(rng, nodes):
    per_wing = 28
    picked = []
    for lo, hi in [(-150.0, -55.0), (55.0, 150.0)]:
        cands = [
            (fan_angle(x, y), i)
            for i, (x, y) in enumerate(nodes)
            if lo <= fan_angle(x, y) <= hi and reachable(x, y)
            and math.hypot(x - CX, y - BUNDLE_Y) < 1450
        ]
        step = (hi - lo) / per_wing
        for b in range(per_wing):
            inside = [i for a, i in cands if lo + b * step <= a < lo + (b + 1) * step]
            if inside:
                picked.append(rng.choice(inside))
    return sorted(set(picked), key=lambda i: fan_angle(*nodes[i]))


def bundle_slots(n):
    """Exit offsets for n threads sorted by fan angle: tight strands, so sorted threads never cross."""
    per = n / STRANDS
    gap = BUNDLE_W / (STRANDS - 1)
    out = []
    for k in range(n):
        s = min(STRANDS - 1, int(k / per))
        first, last = math.ceil(s * per), math.ceil((s + 1) * per) - 1
        sub = k - first - (last - first) / 2
        out.append((s - (STRANDS - 1) / 2) * gap + sub * 1.5)
    return out


def peel_order(ends, nodes):
    """0 for the outermost thread of each side (peels off first), 1 for the innermost."""
    left = [i for i in ends if fan_angle(*nodes[i]) < 0]
    right = [i for i in ends if fan_angle(*nodes[i]) >= 0]
    out = {i: k / max(1, len(left) - 1) for k, i in enumerate(left)}
    out.update({i: 1 - k / max(1, len(right) - 1) for k, i in enumerate(right)})
    return [out[i] for i in ends]


def thread_path(rng, end, slot, inner):
    ex, ey = end
    s = np.array([CX + slot, EXIT_Y - 18])
    top = EXIT_Y + 0.8 * RH
    foot = np.array([CX + slot * (1 - 0.18 * inner), top + inner * (BUNDLE_Y - top)])
    stem = np.linspace(s, foot, 60)
    stem[:, 0] += rng.uniform(0.6, 1.6) * np.sin(np.linspace(0, math.pi, 60) * rng.uniform(1, 3))

    e = np.array([ex, ey])
    dx, dy = ex - foot[0], ey - foot[1]
    side = math.copysign(1, dx)
    p1 = foot + np.array([0, 28 + 0.05 * abs(dx)])
    p2 = np.array([ex - side * 0.42 * abs(dx), min(ey, foot[1] + 40) + 0.12 * max(0, dy)])
    fan = bezier(foot, p1, p2, e, 500)
    tang = np.gradient(fan, axis=0)
    perp = np.stack([-tang[:, 1], tang[:, 0]], 1)
    perp /= np.linalg.norm(perp, axis=1, keepdims=True)
    t = np.linspace(0, 1, len(fan))
    amp, freq, phase = rng.uniform(4, 13), rng.uniform(1.2, 2.8), rng.uniform(0, 6.28)
    fan = fan + perp * (amp * np.sin(2 * math.pi * freq * t + phase) * np.sin(math.pi * t) ** 2)[:, None]
    return np.concatenate([stem, fan[1:]]), np.linalg.norm(foot - s)


def render_mesh(rng, nodes, ends, paths, stems):
    ink = Ink(W, H)
    for (x, y) in nodes:
        for _ in range(rng.randint(2, 4)):
            px, py, heading = x, y, rng.uniform(0, 6.28)
            branch = [(px, py)]
            for _ in range(rng.randint(3, 6)):
                heading += rng.uniform(-0.6, 0.6)
                step = rng.uniform(7, 14)
                px, py = px + math.cos(heading) * step, py + math.sin(heading) * step
                branch.append((px, py))
            ink.line(branch, 0.16, 0.8)
    for i, (x, y) in enumerate(nodes):
        near = sorted(
            (((x - a) ** 2 + (y - b) ** 2), j) for j, (a, b) in enumerate(nodes) if j != i
        )[:2]
        for d2, j in near:
            if d2 > 240**2 or j < i:
                continue
            a, b = nodes[j]
            mx, my = (x + a) / 2 + rng.uniform(-18, 18), (y + b) / 2 + rng.uniform(-18, 18)
            curve = bezier(np.array([x, y]), np.array([mx, my]), np.array([mx, my]), np.array([a, b]), 24)
            ink.line([tuple(p) for p in curve], 0.11, 0.8)
    for pts, stem in zip(paths, stems):
        n = len(pts)
        along = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])
        for k in range(0, n - 1, 2):
            past = along[k] - stem
            v = 0.16 if past < 0 else 0.22 + 0.3 * math.exp(-past / 500)
            ink.line([tuple(pts[k]), tuple(pts[min(k + 2, n - 1)])], v, 0.95)
    end_set = set(ends)
    for i, (x, y) in enumerate(nodes):
        if i in end_set:
            ink.dot(x, y, 3.6, 0.9)
        else:
            ink.dot(x, y, rng.uniform(2.0, 3.0), 0.5)

    core = ink.array()
    glow = gaussian_blur(core, 2.5) * 1.1 + gaussian_blur(core, 12) * 1.5
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    d = np.hypot(xx - CX, yy - BUNDLE_Y)
    mask = np.clip(1.15 - (d - 300) / 1600, 0.3, 1.0)
    mask *= 0.08 + 0.92 * smoothstep(0, 150, box_distance(xx, yy, TEXT_BOX))
    mask *= 1 - smoothstep(HUD_TOP - 80, HUD_TOP + 20, yy)
    mask *= smoothstep(0, 140, np.minimum.reduce([xx, W - xx, yy, H - yy]))
    alpha = np.clip((core + glow) * mask * 0.85, 0, 1)
    rgb = tinted(alpha, core)

    ys, xs = np.nonzero(alpha > 1.5 / 255)
    bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    return rgb[by0:by1, bx0:bx1], alpha[by0:by1, bx0:bx1], (int(bx0), int(by0))


def sd_round_box(x, y, hx, hy, r):
    qx, qy = np.abs(x) - hx + r, np.abs(y) - hy + r
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def cover(d):
    return np.clip(0.5 - d, 0, 1)


def sd_ring_arc(x, y, rm, w):
    """Annulus of mid radius rm with the bottom gap; ends are round."""
    ring = np.abs(np.hypot(x, y) - rm) - w / 2
    ex, ey = rm * math.sin(GAP), rm * math.cos(GAP)
    ends = np.minimum(np.hypot(x - ex, y - ey), np.hypot(x + ex, y - ey)) - w / 2
    return np.where(np.abs(np.arctan2(x, y)) < GAP, ends, ring)


def lug_centers():
    k = LUG_D / math.sqrt(2)
    return [(sx * k, sy * k) for sx in (-1, 1) for sy in (-1, 1)]


def led_centers():
    return [(math.sin(a) * RING_R, math.cos(a) * RING_R) for a in (-LED_A, LED_A)]


class Layers:
    """Premultiplied over-compositing on one square canvas centered on the device."""

    def __init__(self, size):
        self.prem = np.zeros((size, size, 3))
        self.a = np.zeros((size, size))

    def over(self, rgb, a):
        rgb = np.broadcast_to(np.asarray(rgb, dtype=np.float64), self.prem.shape)
        self.prem = rgb * a[..., None] + self.prem * (1 - a[..., None])
        self.a = a + self.a * (1 - a)

    def result(self):
        return self.prem / np.maximum(self.a, 1e-6)[..., None], self.a


def device_grid(size):
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    return xx - c, yy - c


def render_implant(mark):
    size = 2 * math.ceil(1.42 * RH)
    x, y = device_grid(size)
    r = np.hypot(x, y)

    body = (np.abs(x) ** SQUIRCLE + np.abs(y) ** SQUIRCLE) ** (1 / SQUIRCLE) - RH
    lugs = np.min([np.hypot(x - lx, y - ly) for lx, ly in lug_centers()], axis=0)
    body = smin(body, lugs - 0.17 * RH, 0.1 * RH)
    body = smin(body, sd_round_box(x, y - 0.92 * RH, 0.36 * RH, 0.12 * RH, 0.08 * RH), 0.08 * RH)
    hole = lugs - 0.062 * RH

    inside = np.maximum(-body, 0)
    rim = np.exp(-inside / 3.0)
    edge = np.exp(-inside / 16)
    hole_rim = np.exp(-np.maximum(hole, 0) / 2.2)
    light = np.clip(0.5 - (x + y) / (3.2 * RH), 0, 1)
    grain = np.random.default_rng(7).normal(0, 0.018, x.shape)
    shadow = np.exp(-np.maximum(r - PUCK_R, 0) / 9) * (r > PUCK_R - 2)
    bevel = np.exp(-((inside - 7) / 3.5) ** 2) * light
    spec = np.exp(-((x + 0.55 * RH) ** 2 + (y + 0.62 * RH) ** 2) / (2 * (0.22 * RH) ** 2))
    frost_a = np.clip(0.11 + 0.7 * rim + 0.2 * edge + 0.45 * hole_rim + 0.35 * bevel + 0.18 * spec
                      + 0.3 * shadow + grain, 0, 0.92)
    frost_a *= cover(body) * np.clip(0.5 + hole, 0, 1)
    frost_w = np.clip(rim + 0.6 * hole_rim, 0, 1)[..., None]
    frost = np.array([0.74, 0.81, 0.86]) * (1 - frost_w) + WHITE * frost_w
    frost = frost * (1 - 0.75 * shadow[..., None])

    out = Layers(size)
    halo = gaussian_blur(cover(body), 7) * (body > 0)
    out.over(ICE, np.clip(halo * 0.16, 0, 1))
    out.over(frost, frost_a)

    gloss = np.exp(-((x + 0.36 * RH) ** 2 + (y + 0.42 * RH) ** 2) / (2 * (0.34 * RH) ** 2))
    crescent = smoothstep(0.52 * RH, 0.6 * RH, r) * (1 - smoothstep(0.6 * RH, 0.66 * RH, r))
    crescent *= np.clip(-(x + y) / (1.2 * RH), 0, 1)
    puck = 0.022 + 0.07 * gloss + 0.05 * crescent
    out.over(np.stack([puck * 0.95, puck, puck * 1.05], -1), cover(r - PUCK_R))

    out.over(ring_color(light, 0.34), cover(sd_ring_arc(x, y, RING_R, RING_W)))
    for lx, ly in led_centers():
        out.over([0.42, 0.5, 0.52], cover(np.hypot(x - lx, y - ly) - 0.03 * RH))
    out.over([0.06, 0.06, 0.065],
             0.85 * cover(sd_round_box(x, y - (PUCK_R + 0.07 * RH), 0.07 * RH, 0.035 * RH, 0.01 * RH)))
    out.over([0.93, 0.96, 1.0], pad_to(mark, size, size))
    return out.result()


def ring_color(light, level):
    shade = level * (0.88 + 0.12 * light)
    return np.stack([shade * 0.98, shade, shade * 0.99], -1)


def render_ring():
    """The lit ring, faded over the unlit one baked into the implant."""
    size = 2 * math.ceil(RING_R + RING_W)
    x, y = device_grid(size)
    light = np.clip(0.5 - (x + y) / (3.2 * RH), 0, 1)
    return ring_color(light, 0.9), cover(sd_ring_arc(x, y, RING_R, RING_W))


def render_mark_glow(mark):
    pad = 40
    core = pad_to(mark, mark.shape[1] + 2 * pad, mark.shape[0] + 2 * pad)
    a = np.clip(core + gaussian_blur(core, 2.5) * 2.2 + gaussian_blur(core, 10) * 3.0, 0, 1)
    return tinted(a, core), a


def render_halo():
    size = 2 * math.ceil(RING_R + 90)
    x, y = device_grid(size)
    core = cover(sd_ring_arc(x, y, RING_R, RING_W))
    a = np.clip(core + gaussian_blur(core, 5) * 1.2 + gaussian_blur(core, 20) * 1.5, 0, 1)
    return tinted(a, core), a


def render_wordmark(svg, width=560):
    core = svg_alpha(svg, width, "path902")
    core = pad_to(core, width + 60, core.shape[0] + 60)
    a = np.clip(core + gaussian_blur(core, 4) * 0.25 + gaussian_blur(core, 18) * 0.18, 0, 1)
    return tinted(a, core), a


def render_blob(size, layers):
    """layers: (sigma, amplitude) gaussians; the first is the white core."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    r2 = (xx - (size - 1) / 2) ** 2 + (yy - (size - 1) / 2) ** 2
    parts = [amp * np.exp(-r2 / (2 * s * s)) for s, amp in layers]
    a = np.clip(sum(parts), 0, 1)
    return tinted(a, parts[0]), a


def render_box_glow(w, h, rect, value, sigmas):
    ink = Ink(w, h, ss=4)
    ink.draw.rectangle([(rect[0] * 4, rect[1] * 4), (rect[2] * 4 - 1, rect[3] * 4 - 1)],
                       fill=int(255 * value))
    core = ink.array()
    a = core + sum(gaussian_blur(core, s) * k for s, k in sigmas)
    a = np.clip(a, 0, 1)
    return tinted(a, core), a


def render_raster_frame():
    rw = LAYOUT["raster_w"]
    gap = LAYOUT["raster_gap"]
    m = 30
    w, h = rw + 2 * m, RASTER_H + 2 * m
    ink = Ink(w, h, ss=2)
    for row in range(LAYOUT["raster_rows"]):
        y = m + gap / 2 + row * gap
        ink.line([(m, y), (m + rw, y)], 0.07, 0.7)
    for x in range(0, rw + 1, 100):
        ink.line([(m + x, m + RASTER_H + 6), (m + x, m + RASTER_H + (12 if x % 500 == 0 else 9))], 0.3, 0.9)
    b = 16
    for (x, y, sx, sy) in [(m - 10, m - 10, 1, 1), (m + rw + 10, m - 10, -1, 1),
                           (m - 10, m + RASTER_H + 10, 1, -1), (m + rw + 10, m + RASTER_H + 10, -1, -1)]:
        ink.line([(x + sx * b, y), (x, y), (x, y + sy * b)], 0.5, 1.0)
    core = ink.array()
    a = np.clip(core + gaussian_blur(core, 3) * 0.4, 0, 1)
    return tinted(a, core), a, m


def over(canvas, layer, x, y, opacity=1.0):
    rgb, a = layer
    a = a[..., None] * opacity
    region = canvas[y:y + a.shape[0], x:x + a.shape[1]]
    region *= 1 - a
    region += rgb * a


def over_centered(canvas, layer, cx, cy, opacity=1.0):
    h, w = layer[1].shape
    over(canvas, layer, int(cx - w / 2), int(cy - h / 2), opacity)


def render_limine(out, mesh, mesh_at, mark, svg):
    """The linked Plymouth frame with dark zones where Limine prints its menu, branding and comment."""
    canvas = np.zeros((H, W, 3))
    rgb, a = mesh
    mx, my = mesh_at
    yy, xx = np.mgrid[my:my + a.shape[0], mx:mx + a.shape[1]].astype(np.float64)
    keep = (0.06 + 0.94 * smoothstep(0, 150, box_distance(xx, yy, MENU_BOX))) \
        * smoothstep(0, 120, box_distance(xx, yy, BRANDING_BOX))
    over(canvas, (rgb, a * keep), mx, my)
    over_centered(canvas, render_implant(mark), CX, CY)
    over_centered(canvas, render_ring(), CX, CY)
    over_centered(canvas, render_halo(), CX, CY, 0.5)
    over_centered(canvas, render_mark_glow(mark), CX, CY, 0.35)
    dot = render_blob(34, [(1.5, 1.0), (5.0, 0.45)])
    for lx, ly in led_centers():
        over_centered(canvas, dot, CX + lx, CY + ly)
    over_centered(canvas, render_wordmark(svg), CX, LIMINE_WORDMARK_Y)
    out.mkdir(parents=True, exist_ok=True)
    for name, (w, h) in LIMINE.items():
        top = (H - h) // 2
        crop = np.clip(canvas[top:top + h, (W - w) // 2:(W + w) // 2], 0, 1)
        Image.fromarray((crop * 255 + 0.5).astype(np.uint8), "RGB").save(out / f"neuralink-{name}.png", optimize=True)


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def main():
    out = Path(sys.argv[1])
    logic = Path(sys.argv[2]).read_text()
    svg = Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(1024)

    nodes = place_neurons(rng)
    ends = choose_endpoints(rng, nodes)
    paths, stems, samples, lengths = [], [], [], []
    for i, slot, inner in zip(ends, bundle_slots(len(ends)), peel_order(ends, nodes)):
        pts, stem = thread_path(rng, nodes[i], slot, inner)
        even, length = resample(pts, 400)
        paths.append(even)
        stems.append(stem)
        script_pts, _ = resample(pts[::-1], PATH_POINTS)
        samples.append(script_pts)
        lengths.append(length)

    mark = svg_alpha(svg, round(MARK_W), "path5412")
    rgb, a, (mx, my) = render_mesh(rng, nodes, ends, paths, stems)
    save_rgba(out / "mesh.png", rgb, a)
    if len(sys.argv) > 4:
        render_limine(Path(sys.argv[4]), (rgb, a), (mx, my), mark, svg)
    save_rgba(out / "implant.png", *render_implant(mark))
    save_rgba(out / "markglow.png", *render_mark_glow(mark))
    save_rgba(out / "halo.png", *render_halo())
    save_rgba(out / "ring.png", *render_ring())
    save_rgba(out / "wordmark.png", *render_wordmark(svg))
    save_rgba(out / "dot.png", *render_blob(34, [(1.5, 1.0), (5.0, 0.45)]))
    save_rgba(out / "comet.png", *render_blob(40, [(3.6, 0.9), (7.5, 0.4)]))
    save_rgba(out / "pulse.png", *render_blob(72, [(2.4, 1.0), (8.0, 0.55), (20.0, 0.16)]))
    save_rgba(out / "flash.png", *render_blob(150, [(3.2, 1.0), (13.0, 0.5), (34.0, 0.2)]))
    save_rgba(out / "bullet.png", *render_blob(52, [(3.4, 1.0), (9.5, 0.42)]))
    save_rgba(out / "tick.png", *render_box_glow(12, 16, (5, 3, 7, 13), 1.0, [(1.6, 0.6)]))
    save_rgba(out / "cursor.png", *render_box_glow(30, RASTER_H + 40, (14, 12, 16, RASTER_H + 28), 1.0,
                                                   [(2.5, 0.7), (7.0, 0.5)]))
    save_rgba(out / "seg.png", *render_box_glow(16, 14, (2, 6, 14, 8), 1.0, [(1.6, 0.7)]))
    save_rgba(out / "caret.png", *render_box_glow(16, 44, (7, 8, 9, 36), 1.0, [(2.0, 0.6)]))
    save_rgba(out / "head.png", *render_blob(56, [(2.4, 1.0), (10.0, 0.5)]))
    rf_rgb, rf_a, rf_m = render_raster_frame()
    save_rgba(out / "raster.png", rf_rgb, rf_a)

    layout = dict(LAYOUT, mesh_x=mx, mesh_y=my, raster_margin=rf_m, raster_h=RASTER_H)
    lines = ["# Generated by generate.py: geometry in reference canvas pixels, angles in radians."]
    lines += [f"L.{k} = {fmt(v)};" for k, v in layout.items()]
    lines.append(f"D.threads = {len(samples)};")
    lines.append(f"D.points = {PATH_POINTS};")
    for i, (pts, length) in enumerate(zip(samples, lengths)):
        lines.append(f"D.tx[{i}] = [{', '.join(f'{p[0]:.1f}' for p in pts)}];")
        lines.append(f"D.ty[{i}] = [{', '.join(f'{p[1]:.1f}' for p in pts)}];")
        lines.append(f"D.len[{i}] = {length:.1f};")
    (out / "neuralink.script").write_text("\n".join(lines) + "\n\n" + logic)
    print(f"neurons={len(nodes)} threads={len(samples)}", file=sys.stderr)


if __name__ == "__main__":
    main()
