{
  config,
  lib,
  pkgs,
  ...
}: let
  wallpaper = ../config/wallpaper/neuralink-4k.png;
  wallpaperDest = "${config.home.homeDirectory}/Pictures/neuralink-4k.png";
in {
  imports = [./work-secret.nix];

  programs.opencode.settings = {
    model = "amazon-bedrock/anthropic.claude-opus-4-8";
    small_model = "amazon-bedrock/anthropic.claude-sonnet-5";
  };

  home.file.".config/nixos-local-aws/config".source = ../config/aws/work.config;

  home.file."Pictures/neuralink-4k.png".source = wallpaper;

  home.sessionVariables = {
    AWS_CONFIG_FILE = "${config.home.homeDirectory}/.config/nixos-local-aws/config";
    AWS_PROFILE = "BedrockAccess";
    AWS_REGION = "us-west-2";
  };

  # Pin wallpaper on work hosts. Runs after dmsDefaults (when present) so the
  # merge of shared session defaults cannot override the work path.
  home.activation.setWorkWallpaper = lib.hm.dag.entryAfter ["writeBoundary" "dmsDefaults"] ''
    wallpaper="${wallpaperDest}"
    session="$HOME/.local/state/DankMaterialShell/session.json"

    if [ -f "$session" ]; then
      tmp="$(mktemp)"
      if ${pkgs.jq}/bin/jq \
        --arg path "$wallpaper" \
        '.wallpaperPath = $path | .wallpaperCyclingEnabled = false' \
        "$session" > "$tmp"
      then
        mv "$tmp" "$session"
      else
        rm -f "$tmp"
      fi
    fi

    # Live session: DMS on Linux work hosts (niri).
    if command -v dms >/dev/null 2>&1; then
      dms ipc call wallpaper set "$wallpaper" >/dev/null 2>&1 || true
    fi

    # DreamingNeuraBook (darwin) has no DMS; set the desktop picture directly.
    if [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
      osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$wallpaper\"" >/dev/null 2>&1 || true
    fi
  '';
}
