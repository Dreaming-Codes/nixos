#!/usr/bin/env bash
set -euo pipefail

RAZER_CLI="${RAZER_CLI:-razer-cli}"

mode_value() {
  case "${1,,}" in
    balanced | balance | 0) printf '0' ;;
    gaming | game | 1) printf '1' ;;
    creator | create | 2) printf '2' ;;
    silent | quiet | 3) printf '3' ;;
    custom | 4) printf '4' ;;
    *)
      printf 'unknown power mode: %s\n' "$1" >&2
      return 2
      ;;
  esac
}

mode_name() {
  case "$1" in
    0) printf 'balanced' ;;
    1) printf 'gaming' ;;
    2) printf 'creator' ;;
    3) printf 'silent' ;;
    4) printf 'custom' ;;
    *) printf 'unknown' ;;
  esac
}

mode_display() {
  case "$1" in
    0) printf 'Balanced' ;;
    1) printf 'Gaming' ;;
    2) printf 'Creator' ;;
    3) printf 'Silent' ;;
    4) printf 'Custom' ;;
    *) printf 'Unknown' ;;
  esac
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  fi
}

current_source() {
  local supply type online
  for supply in /sys/class/power_supply/*; do
    [ -e "$supply/type" ] || continue
    type="$(<"$supply/type")"
    if [ "$type" = "Mains" ]; then
      online="$(<"$supply/online" 2>/dev/null || printf '0')"
      if [ "$online" = "1" ]; then
        printf 'ac'
      else
        printf 'bat'
      fi
      return
    fi
  done
  printf 'ac'
}

normalize_source() {
  case "${1:-current}" in
    current | active) current_source ;;
    ac | AC) printf 'ac' ;;
    bat | battery | BAT) printf 'bat' ;;
    *)
      printf 'unknown power source: %s\n' "$1" >&2
      return 2
      ;;
  esac
}

read_mode() {
  local source output
  source="$(normalize_source "${1:-current}")"
  output="$("$RAZER_CLI" read power "$source" 2>/dev/null)"
  printf '%s\n' "$output" | sed -n 's/.*pwr: \([0-9]\+\).*/\1/p' | head -n1
}

write_mode() {
  local source mode
  source="$(normalize_source "${1:-current}")"
  shift || true
  if [ "$#" -lt 1 ]; then
    printf 'usage: razer-energy set <current|ac|bat> <mode|custom> [custom-args...]\n' >&2
    return 2
  fi
  mode="$(mode_value "$1")"
  shift
  "$RAZER_CLI" write power "$source" "$mode" "$@"
  notify "Razer Power" "$(mode_display "$mode") on ${source^^}"
}

json_status() {
  local source ac_mode bat_mode current_mode
  source="$(current_source)"
  ac_mode="$(read_mode ac || true)"
  bat_mode="$(read_mode bat || true)"

  if [ -z "$ac_mode" ] || [ -z "$bat_mode" ]; then
    printf '{"ok":false,"text":"!","alt":"error","error":"failed to read Razer power state"}\n'
    return 1
  fi

  if [ "$source" = "ac" ]; then
    current_mode="$ac_mode"
  else
    current_mode="$bat_mode"
  fi

  printf '{"ok":true,"text":"%s","alt":"%s","source":"%s","ac":{"mode":%s,"name":"%s","display":"%s"},"bat":{"mode":%s,"name":"%s","display":"%s"}}\n' \
    "$(mode_display "$current_mode")" \
    "$(mode_name "$current_mode")" \
    "$source" \
    "$ac_mode" "$(mode_name "$ac_mode")" "$(mode_display "$ac_mode")" \
    "$bat_mode" "$(mode_name "$bat_mode")" "$(mode_display "$bat_mode")"
}

toggle_mode() {
  local source current next
  source="$(normalize_source "${1:-current}")"
  current="$(read_mode "$source")"
  case "$current" in
    0) next=1 ;;
    1) next=2 ;;
    2) next=3 ;;
    *) next=0 ;;
  esac
  write_mode "$source" "$next"
}

listen_mode() {
  local last="" current
  while true; do
    current="$(json_status || true)"
    if [ "$current" != "$last" ]; then
      printf '%s\n' "$current"
      last="$current"
    fi
    sleep 5
  done
}

case "${1:-json}" in
  json | status)
    json_status
    ;;
  read)
    read_mode "${2:-current}"
    ;;
  set)
    shift
    write_mode "$@"
    ;;
  toggle)
    toggle_mode "${2:-current}"
    ;;
  listen)
    listen_mode
    ;;
  raw)
    shift
    "$RAZER_CLI" "$@"
    ;;
  write)
    shift
    "$RAZER_CLI" write "$@"
    ;;
  *)
    cat >&2 <<'USAGE'
usage:
  razer-energy [json]
  razer-energy read [current|ac|bat]
  razer-energy toggle [current|ac|bat]
  razer-energy set <current|ac|bat> <balanced|gaming|creator|silent|custom|0-4> [custom-args...]
  razer-energy raw <razer-cli args...>

example:
  razer-energy set ac 4 3 2
  razer-energy raw write power ac 4 3 2
USAGE
    exit 2
    ;;
esac
