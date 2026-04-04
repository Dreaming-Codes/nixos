#!/usr/bin/env bash
# Trigger QuickShell lock screen via named pipe
echo "lock" > "$XDG_RUNTIME_DIR/quickshell-lock"
