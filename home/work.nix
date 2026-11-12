{
  config,
  lib,
  pkgs,
  ...
}: let
  wallpaper = ../config/wallpaper/neuralink-4k.png;
  wallpaperDest = "${config.home.homeDirectory}/Pictures/neuralink-4k.png";

  cpa = config.dreaming.cliProxyApi;
  defaultModel = "work/claude-opus-5-5";

  claudeWorkSettings = pkgs.writeText "claude-work-settings.json" (builtins.toJSON {
    apiKeyHelper = "${pkgs.coreutils}/bin/cat ${cpa.keyFile}";
    env = {
      ANTHROPIC_BASE_URL = cpa.url;
      # /model lists CPA's /v1/models.
      CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "work/claude-opus-5-5";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "work/claude-sonnet-5-5";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "work/claude-haiku-5-5";
    };
  });

  nlk-llm-proxy = pkgs.writeShellApplication {
    name = "nlk-llm-proxy";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
    ];
    text = builtins.replaceStrings ["@llm_proxy_py@"] ["${../secrets/work/llm_proxy.py}"] (
      builtins.readFile ./nlk-llm-proxy.sh
    );
  };

  yq = "${pkgs.yq-go}/bin/yq";

  # Gateway id_tokens live ~65 min and `auth` only renews near expiry, so this
  # runs every few minutes. CLIProxyAPI hot-reloads config.yaml on change.
  cpaGatewaySync = pkgs.writeShellScript "cli-proxy-api-nlk-gateway-sync" ''
    set -euo pipefail
    umask 077
    config="$HOME/.cli-proxy-api/config.yaml"
    key="$(${nlk-llm-proxy}/bin/nlk-llm-proxy auth)"

    providers="$(${pkgs.coreutils}/bin/mktemp)"
    entries="$(${pkgs.coreutils}/bin/mktemp)"
    trap 'rm -f "$providers" "$entries"' EXIT
    current_entries='.api-keys | with_entries(select(.key == "openai-compatibility" or .key == "claude")) | map_values([.[] | select(.name == "nlk-gateway")][0])'
    if ! NLK_GATEWAY_TOKEN="$key" ${pkgs.bun}/bin/bun ${./nlk-gateway-cpa-models.ts} \
      ${../secrets/work/ai-gateway-team-overrides.json} ${cpa.registryFile} > "$providers"; then
      echo "gateway catalog fetch failed, keeping the current model entries" >&2
      ${yq} -o=json "$current_entries" "$config" | ${pkgs.jq}/bin/jq -e 'map_values(del(.keys)) | select(.claude != null and ."openai-compatibility" != null)' > "$providers"
    fi
    ${pkgs.jq}/bin/jq -S --arg k "$key" 'map_values(. + {keys: [{"api-key": $k}]}) | .claude.keys[0].cloak.mode = "never"' "$providers" > "$entries"

    current="$(${yq} -o=json "$current_entries" "$config" | ${pkgs.jq}/bin/jq -S .)"
    [ "$current" = "$(cat "$entries")" ] && exit 0

    ENTRIES="$entries" ${yq} -i '
      load(strenv(ENTRIES)) as $e |
      .api-keys."openai-compatibility" = ([(.api-keys."openai-compatibility" // [])[] | select(.name != "nlk-gateway")] + [$e."openai-compatibility"]) |
      .api-keys.claude = ([(.api-keys.claude // [])[] | select(.name != "nlk-gateway")] + [$e.claude])
    ' "$config"
  '';
in {
  home.packages = [
    nlk-llm-proxy
  ];

  systemd.user.services.cli-proxy-api-nlk-gateway = {
    Unit = {
      Description = "Sync Neuralink AI gateway token into CLIProxyAPI";
      After = ["cli-proxy-api.service"];
      ConditionPathExists = "%h/.cli-proxy-api/config.yaml";
    };
    Install.WantedBy = ["cli-proxy-api.service"];
    Service = {
      Type = "oneshot";
      ExecStart = "${cpaGatewaySync}";
    };
  };

  systemd.user.timers.cli-proxy-api-nlk-gateway = {
    Unit.Description = "Refresh Neuralink AI gateway token in CLIProxyAPI";
    Install.WantedBy = ["timers.target"];
    Timer = {
      OnActiveSec = "1min";
      OnUnitActiveSec = "4min";
    };
  };

  # Stock OpenCode binary (cli.nix); work models go through CLIProxyAPI.
  programs.opencode.settings = {
    enabled_providers = ["cpa-work"];
    provider.cpa-work = {
      npm = "@ai-sdk/openai-compatible";
      name = "CLIProxyAPI work";
      options = {
        baseURL = "${cpa.url}/v1";
        apiKey = "{file:${cpa.keyFile}}";
      };
    };
    model = lib.mkDefault "cpa-work/${defaultModel}";
  };

  dreaming.cliProxyApi.defaultModel = defaultModel;

  # Merge work routing into Claude Code's mutable user settings.
  home.activation.claudeCliProxyApi = lib.hm.dag.entryAfter ["writeBoundary"] ''
    settings="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    [ -s "$settings" ] || echo '{}' > "$settings"
    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${claudeWorkSettings} > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$settings"
  '';

  # Zed reads CPA_WORK_API_KEY, which cli-proxy-api writes into environment.d.
  programs.zed-editor.userSettings.language_models.openai_compatible.cpa-work.api_url = "${cpa.url}/v1";

  home.file."Pictures/neuralink-4k.png".source = wallpaper;

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
  '';
}
