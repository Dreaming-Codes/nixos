{pkgs}:
pkgs.writeShellScriptBin "hash-flake-state" ''
  set -euo pipefail

  CONFIG_DIR="''${1:-$HOME/.nixos}"

  ${pkgs.gitFull}/bin/git -C "$CONFIG_DIR" ls-files -c -o --exclude-standard |
    while IFS= read -r path; do
      file="$CONFIG_DIR/$path"
      if [ -e "$file" ]; then
        printf '%s %s\n' "$path" "$(${pkgs.gitFull}/bin/git hash-object "$file")"
      else
        printf '%s DELETED\n' "$path"
      fi
    done | LC_ALL=C sort | ${pkgs.gitFull}/bin/git hash-object --stdin
''
