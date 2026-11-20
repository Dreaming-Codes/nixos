#!/usr/bin/env python3
"""Step SC200PC controls on raw ISYS captures and print, per stream and per step,
the mean raw level above black and the frame period. The level is taken over the
32x32 tiles that never clip during the run in any stream, so it stays linear in
exposure and compares across streams. Levels from two runs compare only over one
tile set: pass both the same --tiles file.

  sc200pc-probe.py [--streams 2] [--gain 64] [--dwell 1.5] [--tiles FILE] [--trace] STEP...

A STEP is a list of control writes applied as one update, right after a frame starts:
  exposure=1000   vblank=2302,exposure=2119   exposure=1600,short=200
With --streams 2 the sensor's short exposure is captured as well (stream 1) and the
short control sets its exposure.

Needs v4l2-ctl and media-ctl on PATH, numpy, and the camera free (relay stopped).
"""
import argparse
import ctypes
import fcntl
import os
import re
import select
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
CID = {"exposure": 0x00980911, "short": 0x00982958, "vblank": 0x009E0901, "gain": 0x009E0903,
       "dgain": 0x009F0905, "streams": 0x009E0941}
VIDIOC_G_CTRL, VIDIOC_S_EXT_CTRLS = 0xC008561B, 0xC0205648
VIDIOC_SUBSCRIBE_EVENT, VIDIOC_DQEVENT, V4L2_EVENT_FRAME_SYNC = 0x4020565A, 0x80885659, 4
CSI = "Intel IPU7 CSI2 0"
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
    controls = ctypes.create_string_buffer(b"".join(struct.pack("=IIIq", CID[name], 0, 0, value) for name, value in step))
    fcntl.ioctl(fd, VIDIOC_S_EXT_CTRLS, struct.pack("IIIiI4xQ", 0, len(step), 0, 0, 0, ctypes.addressof(controls)))


def read_control(fd, name):
    return struct.unpack("Ii", fcntl.ioctl(fd, VIDIOC_G_CTRL, struct.pack("Ii", CID[name], 0)))[1]


class FrameStart:
    """An exposure written late in a frame lands a frame after the frame length written with it."""

    def __init__(self, subdev):
        self.fd = os.open(subdev, os.O_RDWR | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, VIDIOC_SUBSCRIBE_EVENT, struct.pack("III20x", V4L2_EVENT_FRAME_SYNC, 0, 0))

    def wait(self, timeout=0.5):
        try:
            while True:
                fcntl.ioctl(self.fd, VIDIOC_DQEVENT, bytes(136))
        except OSError:
            pass
        if select.select([], [], [self.fd], timeout)[2]:
            fcntl.ioctl(self.fd, VIDIOC_DQEVENT, bytes(136))


class Stream:
    def __init__(self, index, node):
        self.index, self.node = index, node
        self.levels, self.stamps = [], []
        self.fifo = os.path.join(tempfile.mkdtemp(prefix="sc200pc-probe-"), "frames")
        os.mkfifo(self.fifo)
        self.capture = subprocess.Popen(
            ["v4l2-ctl", "-d", node, "--verbose", "--stream-mmap=4", "--stream-to=" + self.fifo,
             "--set-fmt-video=width=%d,height=%d,pixelformat=BG10" % (WIDTH, HEIGHT)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.threads = [threading.Thread(target=f, daemon=True) for f in (self.read_frames, self.read_stamps)]
        for t in self.threads:
            t.start()

    def read_frames(self):
        size = STRIDE * HEIGHT * 2
        with open(self.fifo, "rb") as stream:
            while len(buf := stream.read(size)) == size:
                px = np.frombuffer(buf, "<u2").reshape(HEIGHT, STRIDE)
                tiles = px[:, :TILES_X * 32].reshape(HEIGHT // 32, 32, TILES_X, 32)
                self.levels.append((tiles.mean((1, 3), dtype=np.float32), tiles.max((1, 3))))

    def read_stamps(self):
        for line in self.capture.stdout:
            if m := re.search(rb"cap dqbuf: \d+ seq: +(\d+) .* ts: ([\d.]+)", line):
                self.stamps.append((int(m.group(1)), float(m.group(2))))

    def stop(self):
        self.capture.terminate()
        for t in self.threads:
            t.join(timeout=5)
        os.unlink(self.fifo)
        os.rmdir(os.path.dirname(self.fifo))

    def frames(self, tiles):
        return [(ts, (ts - pts) * 1000 / (seq - pseq), float(mean[tiles].mean()) - BLACK, seq - pseq - 1)
                for (seq, ts), (mean, _), (pseq, pts) in zip(self.stamps[1:], self.levels[1:], self.stamps)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("steps", nargs="+", type=parse_step, metavar="STEP")
    ap.add_argument("--media", default="/dev/media0")
    ap.add_argument("--streams", type=int, choices=(1, 2), default=1, help="2 captures the short exposure too")
    ap.add_argument("--gain", type=int, default=64, help="analogue gain code, 16 = 1x")
    ap.add_argument("--dwell", type=float, default=1.5, help="seconds per step")
    ap.add_argument("--settle", type=float, default=0.5, help="seconds ignored after each write")
    ap.add_argument("--tiles", help="tile set to measure over, saved by the first run that names it")
    ap.add_argument("--trace", action="store_true", help="print every frame")
    args = ap.parse_args()

    nodes = device_nodes(args.media)
    sensor = next(n for n in nodes if n.startswith("sc200pc "))
    subdev = open(nodes[sensor], "rb+", buffering=0)
    write_controls(subdev, [("streams", args.streams - 1)])
    captures = ["Intel IPU7 ISYS Capture %d" % i for i in range(args.streams)]
    for i, capture in enumerate(captures):
        sh("media-ctl", "-d", args.media, "-l", '"%s":%d -> "%s":0[1]' % (CSI, i + 1, capture))
    sh("media-ctl", "-d", args.media, "-V", '"%s":0 %s, "%s":0 %s' % (sensor, FMT, CSI, FMT))
    write_controls(subdev, [("vblank", 1172), ("gain", args.gain), ("dgain", 128), ("short", 0)] + args.steps[0])

    streams = [Stream(i, nodes[capture]) for i, capture in enumerate(captures)]
    deadline = time.monotonic() + 10
    while any(len(s.levels) < 15 for s in streams):
        if time.monotonic() > deadline or any(s.capture.poll() is not None for s in streams):
            for s in streams:
                s.capture.kill()
            sys.exit("no frames from %s" % ", ".join(s.node for s in streams if len(s.levels) < 15))
        time.sleep(0.05)

    frame_start = FrameStart(nodes[CSI])
    marks = []
    for step in args.steps:
        frame_start.wait()
        begin = time.monotonic()
        write_controls(subdev, step)
        marks.append((begin, time.monotonic(), step, {n: read_control(subdev, n) for n in ("vblank", "exposure")}))
        time.sleep(args.dwell)
    end = time.monotonic()
    for s in streams:
        s.stop()

    unclipped = np.all([peak < CLIP for s in streams for _, peak in s.levels], axis=0)
    if args.tiles and os.path.exists(args.tiles):
        saved = np.load(args.tiles)
        print("%d of the %d saved tiles clip in this run" % ((saved & ~unclipped).sum(), saved.sum()))
        unclipped = saved
    elif args.tiles:
        with open(args.tiles, "wb") as f:
            np.save(f, unclipped)

    for s in streams:
        frames = s.frames(unclipped)
        if args.trace:
            pending = list(marks)
            for ts, period, level, lost in frames:
                while pending and pending[0][0] < ts:
                    begin, done, step, _ = pending.pop(0)
                    print("  write %-34s %.1f ms before this frame end, took %.1f ms"
                          % (",".join("%s=%d" % kv for kv in step), (ts - begin) * 1000, (done - begin) * 1000))
                print("  %10.3f  period %7.3f ms  level %8.2f%s" % (ts, period, level, "  lost %d" % lost if lost else ""))

        print("stream %d: level over %d of %d tiles, %d frames, %d lost" % (
            s.index, unclipped.sum(), unclipped.size, len(frames), sum(f[3] for f in frames)))
        print("%-34s %6s %8s %3s %9s %7s %10s %8s %8s" % (
            "step", "vblank", "exposure", "n", "level", "spread", "period_ms", "spread", "rows"))
        for (begin, done, step, applied), nxt in zip(marks, [m[0] for m in marks[1:]] + [end]):
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
