#!/usr/bin/env bash
# Toggle capture card workspace + input forwarding to DreamingWinzoz.local
# Called by Hyprland keybind: $mod, Home
#
# Flow:
#   If workspace is visible -> kill lan-mouse-grab (if running) and hide workspace
#   If workspace is hidden  -> show workspace, start lan-mouse-grab (blocks), hide on exit

VISIBLE=$(hyprctl monitors -j | jq '[.[].specialWorkspace.name] | any(. == "special:capture-card")')

if [ "$VISIBLE" = "true" ]; then
  pkill -x lan-mouse-grab 2>/dev/null
  hyprctl dispatch togglespecialworkspace capture-card
else
  hyprctl dispatch togglespecialworkspace capture-card
  sleep 0.2
  lan-mouse-grab
  EXIT_CODE=$?
  hyprctl dispatch togglespecialworkspace capture-card
  if [ $EXIT_CODE -ne 0 ]; then
    notify-send -u critical "Capture Card" "lan-mouse-grab exited with error ($EXIT_CODE)"
  fi
fi
