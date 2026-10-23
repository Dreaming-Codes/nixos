{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.services.co2-grafana;
  dashboards = pkgs.writeTextDir "airco2ntrol.json" (builtins.toJSON {
    uid = "airco2ntrol";
    title = "AirCO2ntrol";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-24h";
      to = "now";
    };
    panels = let
      ds = {
        type = "prometheus";
        uid = "prometheus";
      };
      panel = id: title: expr: unit: x: thresholds: {
        inherit id title;
        type = "timeseries";
        datasource = ds;
        gridPos = {
          h = 10;
          w = 12;
          inherit x;
          y = 0;
        };
        fieldConfig.defaults = {
          inherit unit;
          thresholds = {
            mode = "absolute";
            steps = thresholds;
          };
          color.mode = "thresholds";
          custom.thresholdsStyle.mode = "line";
        };
        targets = [
          {
            refId = "A";
            datasource = ds;
            inherit expr;
            legendFormat = title;
          }
        ];
      };
    in [
      (panel 1 "CO2" "airco2ntrol_co2_ppm" "ppm" 0 [
        {
          color = "green";
          value = null;
        }
        {
          color = "yellow";
          value = 1000;
        }
        {
          color = "red";
          value = 1400;
        }
      ])
      (panel 2 "Temperature" "airco2ntrol_temperature_celsius" "celsius" 12 [
        {
          color = "blue";
          value = null;
        }
      ])
    ];
  });
in {
  options.dreaming.services.co2-grafana = {
    enable = lib.mkEnableOption ''
      Prometheus + Grafana (localhost only) with a provisioned dashboard for
      dreaming.hardware.airco2ntrol readings
    '';
    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };
  };

  config = lib.mkIf cfg.enable {
    dreaming.hardware.airco2ntrol.enable = true;

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9090;
      retentionTime = "365d";
      exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        enabledCollectors = ["textfile"];
        extraFlags = ["--collector.textfile.directory=/var/lib/airco2ntrol"];
      };
      scrapeConfigs = [
        {
          job_name = "airco2ntrol";
          scrape_interval = "15s";
          static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];}];
        }
      ];
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.grafanaPort;
        };
        # Local-only box: anonymous read-only viewing; admin login still works.
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
        security.secret_key = "$__file{/var/lib/grafana/secret_key}";
        analytics.reporting_enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString config.services.prometheus.port}";
            isDefault = true;
          }
        ];
        dashboards.settings.providers = [
          {
            name = "airco2ntrol";
            options.path = dashboards;
          }
        ];
      };
    };

    # Generate Grafana's secret_key once instead of committing one.
    systemd.services.grafana.preStart = lib.mkBefore ''
      if [ ! -s /var/lib/grafana/secret_key ]; then
        (umask 077; ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/grafana/secret_key)
      fi
    '';
  };
}
