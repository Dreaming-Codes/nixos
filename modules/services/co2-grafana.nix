{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.services.co2-grafana;
  ds = {
    type = "prometheus";
    uid = "prometheus";
  };
  panel = id: x: title: expr: unit: steps: {
    inherit id title;
    type = "timeseries";
    datasource = ds;
    gridPos = {
      inherit x;
      y = 0;
      w = 12;
      h = 10;
    };
    fieldConfig.defaults = {
      inherit unit;
      color.mode = "thresholds";
      thresholds = {
        mode = "absolute";
        inherit steps;
      };
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
  dashboards = pkgs.writeTextDir "airco2ntrol.json" (builtins.toJSON {
    uid = "airco2ntrol";
    title = "AirCO2ntrol";
    refresh = "30s";
    time = {
      from = "now-24h";
      to = "now";
    };
    panels = [
      (panel 1 0 "CO2" "airco2ntrol_co2_ppm" "ppm" [
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
      (panel 2 12 "Temperature" "airco2ntrol_temperature_celsius" "celsius" [
        {
          color = "blue";
          value = null;
        }
      ])
    ];
  });
in {
  options.dreaming.services.co2-grafana.enable = lib.mkEnableOption "localhost Prometheus + Grafana dashboard for the AirCO2ntrol sensor";

  config = lib.mkIf cfg.enable {
    dreaming.hardware.airco2ntrol.enable = true;

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      retentionTime = "365d";
      exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        extraFlags = ["--collector.disable-defaults" "--collector.textfile" "--collector.textfile.directory=/run/airco2ntrol"];
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
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
        security.secret_key = "$__file{${config.services.grafana.dataDir}/secret_key}";
        analytics.reporting_enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          (ds
            // {
              name = "Prometheus";
              url = "http://127.0.0.1:${toString config.services.prometheus.port}";
              isDefault = true;
            })
        ];
        dashboards.settings.providers = [
          {
            name = "airco2ntrol";
            options.path = dashboards;
          }
        ];
      };
    };

    systemd.services.grafana.preStart = ''
      [ -s secret_key ] || (umask 077; ${lib.getExe pkgs.openssl} rand -hex 32 > secret_key)
    '';
  };
}
