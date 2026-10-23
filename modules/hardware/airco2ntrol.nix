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
    # No valid reading for 60 s (co2mon only logs read errors) -> drop the
    # stale file so node_exporter stops exposing old values.
    last=$SECONDS
    ${lib.getExe co2mon} 2>&1 | while :; do
      rc=0
      read -r -t 15 temp _ ppm _ || rc=$?
      (( rc == 0 || rc > 128 )) || exit 1 # EOF: co2mon exited
      temp=''${temp%,}
      if (( rc != 0 )) || ! [[ $ppm =~ ^[0-9]+$ ]]; then
        [[ -n $temp ]] && (( rc == 0 )) && echo "$temp $ppm" >&2 # co2mon error line
        (( SECONDS - last >= 60 )) && rm -f "$out"
        continue
      fi
      last=$SECONDS
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
          # Also covers BindsTo stops on unplug.
          ExecStopPost = "${pkgs.coreutils}/bin/rm -f ${textfileDir}/airco2ntrol.prom";
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
