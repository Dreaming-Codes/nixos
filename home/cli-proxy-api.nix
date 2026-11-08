{
  pkgs,
  inputs,
  ...
}: let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  cpaUrl = "http://127.0.0.1:8317";
  yq = "${pkgs.yq-go}/bin/yq";

  # Management API rewrites config.yaml, so it lives outside the store. The
  # management key stays in the env file because CPA hashes it inside config.yaml.
  cpaStart = pkgs.writeShellScript "cli-proxy-api-start" ''
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
      .observability.usage."usage-statistics-enabled" = true
    ' "$dir/config.yaml"

    set -a
    . "$dir/management.env"
    set +a
    exec ${llmAgents.cli-proxy-api}/bin/cli-proxy-api -config "$dir/config.yaml"
  '';

  # Keeper defaults to Asia/Shanghai and automatic-timezoned changes /etc/localtime.
  keeperStart = pkgs.writeShellScript "cpa-usage-keeper-start" ''
    tz="$(${pkgs.coreutils}/bin/readlink /etc/localtime)"
    export TZ="''${tz#*/zoneinfo/}"
    exec ${llmAgents.cpa-usage-keeper}/bin/cpa-usage-keeper
  '';
in {
  systemd.user.services.cli-proxy-api = {
    Unit.Description = "CLIProxyAPI";
    Install.WantedBy = ["default.target"];
    Service = {
      ExecStart = "${cpaStart}";
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
        "CPA_BASE_URL=${cpaUrl}"
        "CPA_PUBLIC_URL=${cpaUrl}"
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
}
