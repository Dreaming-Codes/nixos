{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}: let
  wallpaper = ../config/wallpaper/neuralink-4k.png;
  wallpaperDest = "${config.home.homeDirectory}/Pictures/neuralink-4k.png";

  cpa = config.dreaming.cliProxyApi;
  defaultModel = "work/claude-opus-5-5";

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

  # `auth` renews only within 60s of expiry, shorter than the sync interval, so
  # the token used to expire between runs. Renew 10 min ahead instead.
  gatewayToken = pkgs.writeText "nlk-gateway-token.py" ''
    import importlib.util
    import sys

    spec = importlib.util.spec_from_file_location("llm_proxy", "${../secrets/work/llm_proxy.py}")
    llm_proxy = importlib.util.module_from_spec(spec)
    sys.modules["llm_proxy"] = llm_proxy
    spec.loader.exec_module(llm_proxy)
    llm_proxy.NLK_SKEW_SECONDS = 600
    sys.argv = ["llm_proxy", "auth"]
    llm_proxy.main()
  '';

  # Gateway id_tokens live ~60 min. CLIProxyAPI hot-reloads config.yaml on change.
  cpaGatewaySync = pkgs.writeShellScript "cli-proxy-api-nlk-gateway-sync" ''
    set -euo pipefail
    umask 077
    config="$HOME/.cli-proxy-api/config.yaml"
    key="$(${pkgs.python3}/bin/python3 ${gatewayToken})"
    [ -n "$key" ]

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

  # Userpass tokens last 24h and are renewable up to the mount's max TTL, so
  # renew while possible and fall back to a fresh login. Token stays off argv.
  vaultLogin = pkgs.writeShellApplication {
    name = "vault-auto-login";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
    text = ''
      umask 077
      addr="https://vault.int.n7k.io"
      user="lorenzo.rizzotti"
      password_file="${osConfig.sops.secrets.vault_password.path}"
      token_file="$HOME/.vault-token"
      min_ttl=21600

      with_token() {
        printf 'X-Vault-Token: %s\n' "$(cat "$token_file")" \
          | curl -sS --fail --max-time 15 -H @- "$@"
      }

      if [ -s "$token_file" ] && info="$(with_token "$addr/v1/auth/token/lookup-self")"; then
        ttl="$(jq -r '.data.ttl' <<<"$info")"
        if [ "$ttl" -eq 0 ] || [ "$ttl" -gt "$min_ttl" ]; then
          exit 0
        fi
        if [ "$(jq -r '.data.renewable' <<<"$info")" = true ] \
          && renewed="$(with_token -X POST -d '{}' "$addr/v1/auth/token/renew-self")" \
          && [ "$(jq -r '.auth.lease_duration' <<<"$renewed")" -gt "$min_ttl" ]; then
          echo "renewed vault token"
          exit 0
        fi
      fi

      resp="$(jq -Rs '{password: rtrimstr("\n")}' <"$password_file" \
        | curl -sS --fail-with-body --max-time 15 -X POST --data @- "$addr/v1/auth/userpass/login/$user")" || {
        jq -r '.errors // [] | join("; ")' <<<"$resp" >&2 || true
        exit 1
      }
      tmp="$(mktemp "$token_file.XXXXXX")"
      jq -j '.auth.client_token' <<<"$resp" >"$tmp"
      mv "$tmp" "$token_file"
      echo "logged in to vault as $user"
    '';
  };
in {
  home.packages = [
    nlk-llm-proxy
    vaultLogin
  ];

  systemd.user.services.vault-auto-login = {
    Unit.Description = "Keep ~/.vault-token valid for vault.int.n7k.io";
    Service = {
      Type = "oneshot";
      ExecStart = "${vaultLogin}/bin/vault-auto-login";
    };
  };

  # Retries every 30 min, which also covers Tailscale being down at login.
  systemd.user.timers.vault-auto-login = {
    Unit.Description = "Refresh Vault token";
    Install.WantedBy = ["timers.target"];
    Timer = {
      OnActiveSec = "30s";
      OnUnitActiveSec = "30min";
    };
  };

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
