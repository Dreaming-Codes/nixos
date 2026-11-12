{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.hardware.airco2ntrol;
  co2mon = pkgs.callPackage ../../packages/co2mon {};

  # co2mon prints "<temp> °C, <ppm> ppm CO₂" or an error line every ~5 s.
  # The metrics file is dropped after 60 s without a valid reading.
  exporter = pkgs.writeShellScript "airco2ntrol-exporter" ''
    set -euo pipefail
    out=$RUNTIME_DIRECTORY/airco2ntrol.prom
    last=$SECONDS
    ${lib.getExe co2mon} 2>&1 | while IFS= read -r line; do
      if [[ $line =~ ^(-?[0-9.]+)\ .*,\ ([0-9]+)\ ppm ]]; then
        last=$SECONDS
        printf 'airco2ntrol_co2_ppm %s\nairco2ntrol_temperature_celsius %s\n' \
          "''${BASH_REMATCH[2]}" "''${BASH_REMATCH[1]}" > "$out.tmp"
        mv "$out.tmp" "$out"
      else
        echo "$line" >&2
        (( SECONDS - last < 60 )) || rm -f "$out"
      fi
    done
  '';
in {
  options.dreaming.hardware.airco2ntrol.enable = lib.mkEnableOption "TFA AirCO2ntrol Mini (04d9:a052) access and Prometheus textfile exporter";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [co2mon];

    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="04d9", ATTRS{idProduct}=="a052", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="systemd", SYMLINK+="airco2ntrol", ENV{SYSTEMD_WANTS}+="airco2ntrol-exporter.service"
    '';
    users.groups.plugdev = {};
    users.groups.airco2ntrol = {};
    users.users.airco2ntrol = {
      isSystemUser = true;
      group = "airco2ntrol";
    };

    systemd.services.airco2ntrol-exporter = {
      description = "TFA AirCO2ntrol Mini exporter";
      bindsTo = ["dev-airco2ntrol.device"];
      after = ["dev-airco2ntrol.device"];
      serviceConfig = {
        ExecStart = exporter;
        ExecStopPost = "${pkgs.coreutils}/bin/rm -f /run/airco2ntrol/airco2ntrol.prom";
        User = "airco2ntrol";
        Group = "airco2ntrol";
        SupplementaryGroups = ["plugdev"];
        RuntimeDirectory = "airco2ntrol";
        RuntimeDirectoryPreserve = true;
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
