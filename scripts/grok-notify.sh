#!/usr/bin/env bash
set -euo pipefail

niri_window_id() {
  command -v niri >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local wins
  wins=$(niri msg -j windows 2>/dev/null) || return 0
  python3 -c '
import json, sys

wins = json.loads(sys.argv[1])
session = sys.argv[2]
pid = int(sys.argv[3])

if session:
    prefix = session + " |"
    for w in wins:
        title = w.get("title") or ""
        if title == session or title.startswith(prefix):
            print(w["id"])
            raise SystemExit

by_pid = {w.get("pid"): w["id"] for w in wins if w.get("pid")}
seen = set()
while pid and pid != 1 and pid not in seen:
    seen.add(pid)
    if pid in by_pid:
        print(by_pid[pid])
        raise SystemExit
    try:
        with open(f"/proc/{pid}/status", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("PPid:"):
                    pid = int(line.split()[1])
                    break
            else:
                break
    except OSError:
        break
' "$wins" "${ZELLIJ_SESSION_NAME:-}" "$$"
}

wait_and_focus() {
  local wid=$1 title=$2 body=$3 urgency=$4 expire=$5
  local action
  action=$(
    timeout 60 notify-send -a grok-build -u "$urgency" -t "$expire" \
      -A default=Focus -- "$title" "$body" || true
  )
  if [[ $action == default ]]; then
    niri msg action focus-window --id "$wid" || true
  fi
}

event="${1:-${GROK_EVENT:-turn_complete}}"
message="${GROK_MESSAGE:-}"
workspace="${GROK_WORKSPACE_ROOT:-$PWD}"
project="$(basename "$workspace")"

case "$event" in
  --wait-click)
    wait_and_focus "${2:-}" "${3:-}" "${4:-}" "${5:-normal}" "${6:-15000}"
    exit 0
    ;;
  approval_required | permission* | permission_prompt)
    title="Grok needs approval"
    urgency="critical"
    expire=0
    ;;
  question | ask_user_question)
    title="Grok has a question"
    urgency="critical"
    expire=0
    ;;
  agent_error)
    title="Grok error"
    urgency="critical"
    expire=0
    ;;
  task_complete)
    title="Grok task done"
    urgency="normal"
    expire=15000
    ;;
  turn_complete | *)
    title="Grok is done"
    urgency="normal"
    expire=15000
    ;;
esac

if [[ -z $message ]]; then
  body="$project"
else
  body="$project: $message"
fi

if command -v notify-send >/dev/null 2>&1; then
  wid=$(niri_window_id || true)
  if [[ -n ${wid:-} ]]; then
    # Detach so grok's hook timeout cannot kill the click waiter.
    setsid -f "$0" --wait-click "$wid" "$title" "$body" "$urgency" "$expire" >/dev/null 2>&1 || true
  else
    notify-send -a grok-build -u "$urgency" -t "$expire" -- "$title" "$body" || true
  fi
  exit 0
fi

if command -v osascript >/dev/null 2>&1; then
  escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
  }
  osascript -e "display notification \"$(escape "$body")\" with title \"$(escape "$title")\"" || true
fi
