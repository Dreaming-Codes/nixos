{pkgs}:
pkgs.writeShellScriptBin "hash-flake-state" ''
  set -euo pipefail

  CONFIG_DIR="''${1:-$HOME/.nixos}"

  # Allow running over the user-owned repo even as root (e.g. from the
  # activation script), where git would otherwise refuse with
  # "detected dubious ownership". Also neutralize the git-crypt filter: we
  # only need content hashes, and git-crypt may be absent from root's PATH
  # during activation (exit 127), which would abort ls-files/hash-object.
  git() {
    ${pkgs.gitFull}/bin/git \
      -c safe.directory='*' \
      -c filter.git-crypt.clean=cat \
      -c filter.git-crypt.smudge=cat \
      -c filter.git-crypt.required=false \
      "$@"
  }

  git -C "$CONFIG_DIR" ls-files -c -o --exclude-standard |
    while IFS= read -r path; do
      file="$CONFIG_DIR/$path"
      if [ -e "$file" ]; then
        printf '%s %s\n' "$path" "$(git -C "$CONFIG_DIR" hash-object "$file")"
      else
        printf '%s DELETED\n' "$path"
      fi
    done | LC_ALL=C sort | git hash-object --stdin
''
