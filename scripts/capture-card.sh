#!/usr/bin/env bash
# Auto-detect capture card and launch ffplay with low-latency settings
# Detection: finds first /dev/videoN supporting MJPEG 1920x1080@60fps

CAPTURE_DEV=""

for dev in /dev/video*; do
  [ -e "$dev" ] || continue
  # Check if device supports MJPEG capture at 1920x1080 60fps
  formats=$(v4l2-ctl -d "$dev" --list-formats-ext 2>/dev/null)
  if echo "$formats" | grep -q "Motion-JPEG" && \
     echo "$formats" | grep -q "1920x1080" && \
     echo "$formats" | grep -q "60\.000"; then
    CAPTURE_DEV="$dev"
    break
  fi
done

if [ -z "$CAPTURE_DEV" ]; then
  notify-send -u critical "Capture Card" "No capture card detected"
  exit 1
fi

exec ffplay \
  -f v4l2 \
  -input_format mjpeg \
  -framerate 60 \
  -video_size 1920x1080 \
  -fflags nobuffer \
  -flags low_delay \
  -framedrop \
  -strict experimental \
  -vf setpts=0 \
  -fs \
  -window_title 'Capture Card 60fps' \
  "$CAPTURE_DEV"
