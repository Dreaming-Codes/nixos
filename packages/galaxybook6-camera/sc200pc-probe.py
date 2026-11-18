#!/usr/bin/env python3
"""Step SC200PC controls on a raw ISYS capture and print, per step, the mean
raw level above black and the frame period. The level is taken over the 32x32
tiles that never clip during the run, so it stays linear in exposure. Levels
from two runs compare only over one tile set: pass both the same --tiles file.

  sc200pc-probe.py [--gain 64] [--dwell 1.5] [--tiles FILE] [--trace] STEP...

A STEP is a list of control writes issued back to back in the order given:
  exposure=1000   vblank=2302,exposure=2119   exposure=500,vblank=1172

Needs v4l2-ctl and media-ctl on PATH, numpy, and the camera free (relay stopped).
"""
import argparse
import fcntl
import os
import re
import statistics
import struct
import subprocess
import sys
import tempfile
import threading
import time

import numpy as np

WIDTH, HEIGHT, STRIDE, BLACK = 1928, 1088, 1952, 64
TILES_X, CLIP = WIDTH // 32, 1000
ROW_US = 33320.7 / 2260
CID = {"exposure": 0x00980911, "vblank": 0x009E0901, "gain": 0x009E0903, "dgain": 0x009F0905}
VIDIOC_G_CTRL, VIDIOC_S_CTRL = 0xC008561B, 0xC008561C
CSI, CAPTURE = "Intel IPU7 CSI2 0", "Intel IPU7 ISYS Capture 0"
FMT = "[fmt:SBGGR10_1X10/%dx%d]" % (WIDTH, HEIGHT)


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def device_nodes(media):
    nodes, name = {}, None
    for line in sh("media-ctl", "-d", media, "-p").splitlines():
        if m := re.match(r"- entity \d+: (.+) \(\d+ pad", line):
            name = m.group(1)
        if m := re.search(r"device node name (\S+)", line):
            nodes[name] = m.group(1)
    return nodes


def parse_step(text):
    return [(k, int(v, 0)) for k, v in (kv.split("=") for kv in text.split(","))]


def write_controls(fd, step):
    for name, value in step:
        fcntl.ioctl(fd, VIDIOC_S_CTRL, struct.pack("Ii", CID[name], value))


def read_control(fd, name):
    return struct.unpack("Ii", fcntl.ioctl(fd, VIDIOC_G_CTRL, struct.pack("Ii", CID[name], 0)))[1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("steps", nargs="+", type=parse_step, metavar="STEP")
    ap.add_argument("--media", default="/dev/media0")
    ap.add_argument("--gain", type=int, default=64, help="analogue gain code, 16 = 1x")
    ap.add_argument("--dwell", type=float, default=1.5, help="seconds per step")
    ap.add_argument("--settle", type=float, default=0.5, help="seconds ignored after each write")
    ap.add_argument("--tiles", help="tile set to measure over, saved by the first run that names it")
    ap.add_argument("--trace", action="store_true", help="print every frame")
    args = ap.parse_args()

    nodes = device_nodes(args.media)
    sensor = next(n for n in nodes if n.startswith("sc200pc "))
    sh("media-ctl", "-d", args.media, "-l", '"%s":1 -> "%s":0[1]' % (CSI, CAPTURE))
    sh("media-ctl", "-d", args.media, "-V",
       '"%s":0 %s, "%s":0 %s, "%s":1 %s' % (sensor, FMT, CSI, FMT, CSI, FMT))

    subdev = open(nodes[sensor], "rb+", buffering=0)
    write_controls(subdev, [("vblank", 1172), ("gain", args.gain), ("dgain", 128)] + args.steps[0])

    fifo = os.path.join(tempfile.mkdtemp(prefix="sc200pc-probe-"), "frames")
    os.mkfifo(fifo)
    capture = subprocess.Popen(
        ["v4l2-ctl", "-d", nodes[CAPTURE], "--verbose", "--stream-mmap=4", "--stream-to=" + fifo,
         "--set-fmt-video=width=%d,height=%d,pixelformat=BG10" % (WIDTH, HEIGHT)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    levels, stamps = [], []

    def read_frames():
        size = STRIDE * HEIGHT * 2
        with open(fifo, "rb") as stream:
            while len(buf := stream.read(size)) == size:
                px = np.frombuffer(buf, "<u2").reshape(HEIGHT, STRIDE)
                tiles = px[:, :TILES_X * 32].reshape(HEIGHT // 32, 32, TILES_X, 32)
                levels.append((tiles.mean((1, 3), dtype=np.float32), tiles.max((1, 3))))

    def read_stamps():
        for line in capture.stdout:
            if m := re.search(rb"cap dqbuf: \d+ seq: +(\d+) .* ts: ([\d.]+)", line):
                stamps.append((int(m.group(1)), float(m.group(2))))

    threads = [threading.Thread(target=f, daemon=True) for f in (read_frames, read_stamps)]
    for t in threads:
        t.start()
    deadline = time.monotonic() + 10
    while len(levels) < 15:
        if time.monotonic() > deadline or capture.poll() is not None:
            capture.kill()
            sys.exit("no frames from %s" % nodes[CAPTURE])
        time.sleep(0.05)

    marks = []
    for step in args.steps:
        start = time.monotonic()
        write_controls(subdev, step)
        marks.append((start, time.monotonic(), step, {n: read_control(subdev, n) for n in ("vblank", "exposure")}))
        time.sleep(args.dwell)
    end = time.monotonic()
    capture.terminate()
    for t in threads:
        t.join(timeout=5)
    os.unlink(fifo)
    os.rmdir(os.path.dirname(fifo))

    unclipped = np.all([peak < CLIP for _, peak in levels], axis=0)
    if args.tiles and os.path.exists(args.tiles):
        saved = np.load(args.tiles)
        print("%d of the %d saved tiles clip in this run" % ((saved & ~unclipped).sum(), saved.sum()))
        unclipped = saved
    elif args.tiles:
        with open(args.tiles, "wb") as f:
            np.save(f, unclipped)
    frames = []
    for (seq, ts), (mean, _), (pseq, pts) in zip(stamps[1:], levels[1:], stamps):
        frames.append((ts, (ts - pts) * 1000 / (seq - pseq), float(mean[unclipped].mean()) - BLACK, seq - pseq - 1))

    if args.trace:
        pending = list(marks)
        for ts, period, level, lost in frames:
            while pending and pending[0][0] < ts:
                start, done, step, _ = pending.pop(0)
                print("  write %-34s %.1f ms before this frame end, took %.1f ms"
                      % (",".join("%s=%d" % kv for kv in step), (ts - start) * 1000, (done - start) * 1000))
            print("  %10.3f  period %7.3f ms  level %8.2f%s" % (ts, period, level, "  lost %d" % lost if lost else ""))

    print("level over %d of %d tiles, %d frames, %d lost" % (
        unclipped.sum(), unclipped.size, len(frames), sum(f[3] for f in frames)))
    print("%-34s %6s %8s %3s %9s %7s %10s %8s %8s" % (
        "step", "vblank", "exposure", "n", "level", "spread", "period_ms", "spread", "rows"))
    for (start, done, step, applied), nxt in zip(marks, [m[0] for m in marks[1:]] + [end]):
        sel = [f for f in frames if done + args.settle < f[0] < nxt]
        if len(sel) < 3:
            print("%-34s too few frames (%d)" % (",".join("%s=%d" % kv for kv in step), len(sel)))
            continue
        lv, pd = [f[2] for f in sel], [f[1] for f in sel]
        period = statistics.median(pd)
        print("%-34s %6d %8d %3d %9.2f %7.2f %10.3f %8.3f %8.1f" % (
            ",".join("%s=%d" % kv for kv in step), applied["vblank"], applied["exposure"], len(sel),
            statistics.median(lv), max(lv) - min(lv), period, max(pd) - min(pd), period * 1000 / ROW_US))


if __name__ == "__main__":
    main()
