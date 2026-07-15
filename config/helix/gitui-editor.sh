#!/usr/bin/env bash
# Open a file in the Helix instance under Zellij (used as GIT_EDITOR from gitui).
# gitui invokes: $GIT_EDITOR <path>
set -euo pipefail

file="${1:?usage: gitui-editor.sh <path>}"

# Helix single-quote escaping: ' -> '\''
helix_path=${file//\'/\'\\\'\'}

# Hide floating gitui and focus Helix
zellij action toggle-floating-panes
# Ensure normal mode, then open the file
zellij action write 27 # Escape
zellij action write-chars ":open '${helix_path}'"
zellij action write 13 # Enter
