{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.dreaming.hardware.airco2ntrol;
  co2mon = pkgs.callPackage "${self}/packages/co2mon" {};
  textfileDir = "/var/lib/airco2ntrol";

  # co2mon prints "<temp> °C, <ppm> ppm CO₂" every 5 s; turn each line into a
  # Prometheus textfile (written atomically) for node_exporter.
  exporter = pkgs.writeShellScript "airco2ntrol-exporter" ''
    set -euo pipefail
    out=${textfileDir}/airco2ntrol.prom
    ${lib.getExe co2mon} | while read -r temp _ ppm _; do
      temp=''${temp%,}
      [[ $ppm =~ ^[0-9]+$ ]] || continue
      printf '%s\n' \
        "# HELP airco2ntrol_co2_ppm CO2 concentration (NDIR)" \
        "# TYPE airco2ntrol_co2_ppm gauge" \
        "airco2ntrol_co2_ppm $ppm" \
        "# HELP airco2ntrol_temperature_celsius Ambient temperature" \
        "# TYPE airco2ntrol_temperature_celsius gauge" \
        "airco2ntrol_temperature_celsius $temp" > "$out.tmp"
      mv "$out.tmp" "$out"
      echo "co2=''${ppm}ppm temp=''${temp}C"
    done
  '';
in {
  options.dreaming.hardware.airco2ntrol = {
    enable = lib.mkEnableOption ''
      TFA Dostmann AirCO2ntrol Mini (Holtek/ZyAura USB HID 04d9:a052):
      udev access rule, `co2mon` CLI, and a logging/exporter service
    '';
    exporter.enable =
      lib.mkEnableOption "systemd service exposing readings as Prometheus textfile metrics"
      // {default = true;};
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [co2mon];

      # Seat user (uaccess) and plugdev get rw; stable /dev/airco2ntrol symlink.
      services.udev.extraRules = ''
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="04d9", ATTRS{idProduct}=="a052", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="systemd", SYMLINK+="airco2ntrol", ENV{SYSTEMD_WANTS}+="airco2ntrol-exporter.service"
      '';
      users.groups.plugdev = {};
    }
    (lib.mkIf cfg.exporter.enable {
      users.users.airco2ntrol = {
        isSystemUser = true;
        group = "airco2ntrol";
      };
      users.groups.airco2ntrol = {};
      systemd.services.airco2ntrol-exporter = {
        description = "TFA AirCO2ntrol Mini reader";
        bindsTo = ["dev-airco2ntrol.device"];
        after = ["dev-airco2ntrol.device"];
        serviceConfig = {
          ExecStart = exporter;
          # Static user (not DynamicUser): /var/lib/private is 0700 and
          # node_exporter must read the textfile.
          User = "airco2ntrol";
          Group = "airco2ntrol";
          SupplementaryGroups = ["plugdev"];
          StateDirectory = "airco2ntrol";
          StateDirectoryMode = "0755";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
    })
  ]);
}
