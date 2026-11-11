{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.dreaming.cliProxyApi;
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  personal = cfg.personalModels;
  yq = "${pkgs.yq-go}/bin/yq";
  keyCommand = "${pkgs.coreutils}/bin/cat ${cfg.keyFile}";

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

  grokProviderToml = ''
    [model_providers.cli-proxy-api]
    base_url = "${cfg.url}/v1"

    [model_providers.cli-proxy-api.auth]
    command = "${keyCommand}"

  '';

  # Rewrites the [model.*] tables and the cli-proxy-api provider in
  # ~/.grok/config.toml, and turns off the fleet managed_config fetch.
  grokModelsSync = pkgs.writeShellScript "grok-cli-proxy-api-models" ''
    set -euo pipefail
    dir="$HOME/.grok"
    config="$dir/config.toml"
    mkdir -p "$dir"
    rm -f "$dir/managed_config.toml"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$dir/.config.toml.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    [ -f "$config" ] || : > "$config"
    ${pkgs.gawk}/bin/awk '
      /^# (nlk-gateway-models|cli-proxy-api) \(home-manager/ { next }
      /^\[/ {
        skip = ($0 ~ /^\[model\./ || $0 ~ /^\[model_providers\.cli-proxy-api[].]/)
        features = ($0 == "[features]")
        if (features) has_features = 1
      }
      features && /^[ \t]*managed_config[ \t]*=/ { next }
      !skip { lines[n++] = $0 }
      features && /^\[features\]$/ { lines[n++] = "managed_config = false" }
      END {
        while (n > 0 && lines[n - 1] ~ /^[ \t]*$/) n--
        for (i = 0; i < n; i++) print lines[i]
        if (n > 0) print ""
        if (!has_features) print "[features]\nmanaged_config = false\n"
      }
    ' "$config" > "$tmp"
    {
      echo '# cli-proxy-api (home-manager; do not edit)'
      cat ${grokFragment}
    } >> "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"
  '';
  grokFragment = pkgs.writeText "grok-cli-proxy-api.toml" (grokProviderToml + cfg.grokModels);

  quote = s: ''"${lib.escape ["\\" "\""] s}"'';
  # Root assignments stay above any [table]. Keys after a header belong to that table.
  codexRoot = pkgs.writeText "codex-cli-proxy-api-root.toml" ''
    # cli-proxy-api (home-manager; do not edit)
    model_provider = "cli-proxy-api"
    model = ${quote cfg.codexModel}
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
      ANTHROPIC_MODEL = personal.claudeOpusModelId;
      ANTHROPIC_DEFAULT_OPUS_MODEL = personal.claudeOpusModelId;
      ANTHROPIC_DEFAULT_SONNET_MODEL = personal.claudeSonnetModelId;
      ANTHROPIC_DEFAULT_HAIKU_MODEL = personal.claudeHaikuModelId;
      CLAUDE_CODE_SUBAGENT_MODEL = personal.claudeHaikuModelId;
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
    personalModels = lib.mkOption {
      type = lib.types.attrs;
      default = import ./cpa-personal-models.nix {
        inherit lib;
        catalog = cfg.registryFile;
      };
      readOnly = true;
    };
    grokModels = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "[model.*] tables for ~/.grok/config.toml that use the cli-proxy-api provider.";
    };
    codexModel = lib.mkOption {
      type = lib.types.str;
      description = "Model id Codex requests through CLIProxyAPI.";
    };
  };

  config = {
    dreaming.cliProxyApi.grokModels = personal.grokConfigModelsToml;
    dreaming.cliProxyApi.codexModel = lib.mkDefault personal.defaultModelId;

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
      models = personal.opencodeModels;
    };

    home.activation.grokCliProxyApiModels =
      lib.hm.dag.entryAfter ["writeBoundary"] "run ${grokModelsSync}";
    home.activation.codexCliProxyApi =
      lib.hm.dag.entryAfter ["writeBoundary"] "run ${codexConfigSync}";

    systemd.user.services.cli-proxy-api = {
      Unit.Description = "CLIProxyAPI";
      Install.WantedBy = ["default.target"];
      Service = {
        ExecStartPre = "${cpaInit}";
        ExecStart = "${llmAgents.cli-proxy-api}/bin/cli-proxy-api -config %h/.cli-proxy-api/config.yaml";
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
