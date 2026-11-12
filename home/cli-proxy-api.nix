{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.dreaming.cliProxyApi;
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  cliProxyApi = import ../packages/cli-proxy-api {inherit inputs pkgs;};
  yq = "${pkgs.yq-go}/bin/yq";
  keyCommand = "${pkgs.coreutils}/bin/cat ${cfg.keyFile}";
  # Clients read CPA's live model list through this shared catalog.
  cpaModels = ../config/cpa-models;
  zedCpaModels = "${pkgs.bun}/bin/bun ${cpaModels}/zed.ts";

  # Management API rewrites config.yaml, so it lives outside the store. The
  # management key stays in the env file because CPA hashes it inside config.yaml.
  cpaInit = pkgs.writeShellScript "cli-proxy-api-init" ''
    set -euo pipefail
    umask 077
    dir="$HOME/.cli-proxy-api"
    mkdir -p "$dir"

    if [ ! -s "$dir/management.env" ]; then
      key="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
      printf 'MANAGEMENT_PASSWORD=%s\nCPA_MANAGEMENT_KEY=%s\n' "$key" "$key" > "$dir/management.env"
    fi

    if [ ! -s "$dir/config.yaml" ]; then
      CLIENT_KEY="$(${pkgs.openssl}/bin/openssl rand -hex 24)" \
        ${yq} -n '."config-version" = 8 | .access."api-keys" = [strenv(CLIENT_KEY)]' > "$dir/config.yaml"
    fi
    ${yq} -i '
      .server.host = "127.0.0.1" |
      .server.port = 8317 |
      .oauth."auth-dir" = "~/.cli-proxy-api" |
      .observability.usage."usage-statistics-enabled" = true |
      .routing."force-model-prefix" = true
    ' "$dir/config.yaml"

    # Clients read the first client key from a file or from the environment.
    client_key="$(${yq} '.access."api-keys"[0]' "$dir/config.yaml")"
    printf '%s\n' "$client_key" > "${cfg.keyFile}"
    env_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
    mkdir -p "$env_dir"
    printf 'CPA_WORK_API_KEY=%s\nCPA_PERSONAL_API_KEY=%s\n' "$client_key" "$client_key" > "$env_dir/81-cli-proxy-api.conf"
    ${pkgs.systemd}/bin/systemctl --user set-environment \
      "CPA_WORK_API_KEY=$client_key" "CPA_PERSONAL_API_KEY=$client_key"
  '';

  # Keeper defaults to Asia/Shanghai and automatic-timezoned changes /etc/localtime.
  keeperStart = pkgs.writeShellScript "cpa-usage-keeper-start" ''
    tz="$(${pkgs.coreutils}/bin/readlink /etc/localtime)"
    export TZ="''${tz#*/zoneinfo/}"
    exec ${llmAgents.cpa-usage-keeper}/bin/cpa-usage-keeper
  '';

  grokAuth = pkgs.writeShellScript "grok-cli-proxy-api-auth" ''
    printf '{"access_token":"%s"}\n' "$(${keyCommand})"
  '';
  # Keys home-manager owns, per table. [model.*] tables and the old
  # cli-proxy-api provider are dropped so the CPA model list wins.
  grokConfigAwk = pkgs.writeText "grok-config.awk" ''
    BEGIN {
      tables[1] = "[features]"; keys[1] = "managed_config"
      lines[1] = "managed_config = false"
      tables[2] = "[endpoints]"; keys[2] = "models_base_url"
      lines[2] = "models_base_url = \"${cfg.url}/v1\""
      tables[3] = "[auth]"; keys[3] = "auth_provider_command|auth_provider_label"
      lines[3] = "auth_provider_command = \"${grokAuth}\"\nauth_provider_label = \"CLIProxyAPI\""
      for (i = 1; i <= 3; i++) index_of[tables[i]] = i
    }
    /^# (nlk-gateway-models|cli-proxy-api) \(home-manager/ { next }
    /^\[/ {
      table = $0
      sub(/[ \t]*(#.*)?$/, "", table)
      skip = (table ~ /^\[model\./ || table ~ /^\[model_providers\.cli-proxy-api[].]/)
      t = (table in index_of) ? index_of[table] : 0
    }
    skip { next }
    t && $0 ~ ("^[ \t]*(" keys[t] ")[ \t]*=") { next }
    # Model ids were personal-<id> slugs before the CPA list.
    table == "[models]" { sub(/^[ \t]*default[ \t]*=[ \t]*"personal-/, "default = \"personal/") }
    { out[n++] = $0 }
    /^\[/ && t { out[n++] = lines[t]; seen[t] = 1 }
    END {
      while (n > 0 && out[n - 1] ~ /^[ \t]*$/) n--
      for (i = 0; i < n; i++) print out[i]
      for (i = 1; i <= 3; i++) if (!seen[i]) printf "%s%s\n%s\n", (n || i > 1 ? "\n" : ""), tables[i], lines[i]
    }
  '';
  # Grok fetches models from CPA's /v1/models and signs in through grokAuth.
  grokConfigSync = pkgs.writeShellScript "grok-cli-proxy-api-config" ''
    set -euo pipefail
    dir="$HOME/.grok"
    config="$dir/config.toml"
    mkdir -p "$dir"
    rm -f "$dir/managed_config.toml"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$dir/.config.toml.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    [ -f "$config" ] || : > "$config"
    ${pkgs.gawk}/bin/awk -f ${grokConfigAwk} "$config" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"
  '';

  quote = s: ''"${lib.escape ["\\" "\""] s}"'';
  # Root assignments stay above any [table]. Keys after a header belong to that table.
  codexRoot = pkgs.writeText "codex-cli-proxy-api-root.toml" ''
    # cli-proxy-api (home-manager; do not edit)
    model_provider = "cli-proxy-api"
    model = ${quote cfg.defaultModel}
  '';
  codexProvider = pkgs.writeText "codex-cli-proxy-api-provider.toml" ''
    [model_providers.cli-proxy-api]
    name = "CLIProxyAPI"
    base_url = "${cfg.url}/v1"
    wire_api = "responses"
    requires_openai_auth = false

    [model_providers.cli-proxy-api.auth]
    command = "${pkgs.coreutils}/bin/cat"
    args = [${quote cfg.keyFile}]
  '';
  # Codex rewrites ~/.codex/config.toml, so only the provider and the root model are replaced.
  codexConfigSync = pkgs.writeShellScript "codex-cli-proxy-api-config" ''
    set -euo pipefail
    dir="$HOME/.codex"
    config="$dir/config.toml"
    mkdir -p "$dir"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$dir/.config.toml.XXXXXX")"
    preserved="$(${pkgs.coreutils}/bin/mktemp)"
    trap 'rm -f "$tmp" "$preserved"' EXIT

    [ -f "$config" ] || : > "$config"
    ${pkgs.gawk}/bin/awk '
      /^# cli-proxy-api \(home-manager/ { next }
      /^\[/ {
        section = $0
        skip = (section ~ /^\[model_providers\.cli-proxy-api(\.[^]]+)?\][ \t]*(#.*)?$/)
      }
      skip { next }
      section == "" && /^[ \t]*model_provider[ \t]*=/ { next }
      section == "" && /^[ \t]*model[ \t]*=/ { next }
      { lines[n++] = $0 }
      END {
        start = 0
        while (start < n && lines[start] ~ /^[ \t]*$/) start++
        while (n > start && lines[n - 1] ~ /^[ \t]*$/) n--
        for (i = start; i < n; i++) print lines[i]
      }
    ' "$config" > "$preserved"
    {
      cat ${codexRoot}
      if [ -s "$preserved" ]; then
        echo
        cat "$preserved"
      fi
      echo
      cat ${codexProvider}
      echo
    } > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"
  '';

  # --settings outranks ~/.claude/settings.json, so these env values win.
  claudePersonalSettings = pkgs.writeText "claude-personal-settings.json" (builtins.toJSON {
    apiKeyHelper = keyCommand;
    env = {
      ANTHROPIC_BASE_URL = cfg.url;
      ANTHROPIC_MODEL = "personal/claude-opus-5-5";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "personal/claude-opus-5-5";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "personal/claude-sonnet-5-5";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "personal/claude-haiku-5-5";
      CLAUDE_CODE_SUBAGENT_MODEL = "personal/claude-haiku-5-5";
    };
  });
in {
  options.dreaming.cliProxyApi = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8317";
      readOnly = true;
    };
    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cli-proxy-api/client.key";
      readOnly = true;
    };
    registryFile = lib.mkOption {
      type = lib.types.str;
      default = "${llmAgents.cli-proxy-api.src}/internal/registry/models/models.json";
      readOnly = true;
    };
    defaultModel = lib.mkOption {
      type = lib.types.str;
      description = "CLIProxyAPI model id that Codex, Pi and Zed start with.";
    };
  };

  config = {
    dreaming.cliProxyApi.defaultModel = lib.mkDefault "personal/grok-4.7";

    home.packages = [
      (pkgs.writeShellScriptBin "claude-personal" ''
        exec claude --settings ${claudePersonalSettings} "$@"
      '')
    ];

    # Hide OpenCode's built-in providers (anthropic, openai, opencode).
    programs.opencode.settings.enabled_providers = ["cpa-personal"];
    programs.opencode.settings.provider.cpa-personal = {
      npm = "@ai-sdk/openai-compatible";
      name = "CLIProxyAPI personal";
      options = {
        baseURL = "${cfg.url}/v1";
        apiKey = "{file:${cfg.keyFile}}";
      };
    };
    programs.pi-coding-agent.settings = {
      defaultProvider = "cpa-${lib.head (lib.splitString "/" cfg.defaultModel)}";
      inherit (cfg) defaultModel;
    };
    home.file."${config.programs.pi-coding-agent.configDir}/extensions/cpa-models/index.ts".text = ''
      export { default } from "${cpaModels}/pi.ts"
    '';

    # Zed reads CPA_PERSONAL_API_KEY. zedCpaModels fills in available_models
    # for every cpa-* provider in settings.json.
    programs.zed-editor.userSettings = {
      language_models.openai_compatible.cpa-personal.api_url = "${cfg.url}/v1";
      agent.default_model = {
        provider = "cpa-${lib.head (lib.splitString "/" cfg.defaultModel)}";
        model = cfg.defaultModel;
      };
    };
    systemd.user.services.zed-cpa-models = {
      Unit = {
        Description = "Write CLIProxyAPI models into Zed settings";
        After = ["cli-proxy-api.service"];
        ConditionPathExists = "%h/.config/zed/settings.json";
      };
      Service = {
        Type = "oneshot";
        ExecStart = zedCpaModels;
      };
    };
    systemd.user.timers.zed-cpa-models = {
      Unit.Description = "Refresh CLIProxyAPI models in Zed settings";
      Install.WantedBy = ["timers.target"];
      Timer = {
        OnActiveSec = "2min";
        OnUnitActiveSec = "15min";
      };
    };
    home.activation.zedCpaModels = lib.hm.dag.entryAfter ["zedSettingsActivation"] ''
      run ${zedCpaModels} || echo "zed-cpa-models: CLIProxyAPI unreachable, keeping Zed models" >&2
    '';

    xdg.configFile."opencode/plugins/cpa-models/index.ts".text = ''
      export { default } from "${cpaModels}/opencode.ts"
    '';

    home.activation.grokCliProxyApi =
      lib.hm.dag.entryAfter ["writeBoundary"] "run ${grokConfigSync}";
    home.activation.codexCliProxyApi =
      lib.hm.dag.entryAfter ["writeBoundary"] "run ${codexConfigSync}";

    systemd.user.services.cli-proxy-api = {
      Unit.Description = "CLIProxyAPI";
      Install.WantedBy = ["default.target"];
      Service = {
        ExecStartPre = "${cpaInit}";
        ExecStart = "${cliProxyApi}/bin/cli-proxy-api -config %h/.cli-proxy-api/config.yaml";
        # Optional because ExecStartPre creates it on first start.
        EnvironmentFile = "-%h/.cli-proxy-api/management.env";
        WorkingDirectory = "%h";
        Restart = "on-failure";
      };
    };

    systemd.user.services.cpa-usage-keeper = {
      Unit = {
        Description = "CPA Usage Keeper";
        BindsTo = ["cli-proxy-api.service"];
        After = ["cli-proxy-api.service"];
      };
      Install.WantedBy = ["cli-proxy-api.service"];
      Service = {
        ExecStart = "${keeperStart}";
        EnvironmentFile = "%h/.cli-proxy-api/management.env";
        Environment = [
          "CPA_BASE_URL=${cfg.url}"
          "CPA_PUBLIC_URL=${cfg.url}"
          "APP_HOST=127.0.0.1"
          "APP_PORT=8318"
          "AUTH_ENABLED=false"
          "WORK_DIR=%S/cpa-usage-keeper"
          "LOG_FILE_ENABLED=false"
        ];
        StateDirectory = "cpa-usage-keeper";
        WorkingDirectory = "%S/cpa-usage-keeper";
        Restart = "on-failure";
      };
    };
  };
}
