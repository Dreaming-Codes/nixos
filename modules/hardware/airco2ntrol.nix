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

  beep = pkgs.runCommand "airco2ntrol-beep.wav" {nativeBuildInputs = [pkgs.sox];} ''
    sox -n -r 48000 $out synth 0.15 sine 2000 pad 0 0.1 repeat 1 pad 0 0.3
  '';
  # Beeps at 100% on every sink until a key press (read from evdev, so it works
  # on the lock screen) or CO2 drops below the threshold. Sink volumes are
  # restored afterwards.
  alarm = pkgs.writeShellScript "airco2ntrol-alarm" ''
    f=/run/airco2ntrol/airco2ntrol.prom
    threshold=${toString cfg.alarmPpm}
    saved=()

    ppm() {
      local name value
      [[ -r $f ]] && while read -r name value; do
        [[ $name == airco2ntrol_co2_ppm ]] && echo "$value" && return
      done < "$f"
      echo 0
    }

    restore() {
      local e s v m
      for e in "''${saved[@]}"; do
        read -r s v m <<< "$e"
        pactl set-sink-volume "$s" "$v"
        pactl set-sink-mute "$s" "$m"
      done
      saved=()
    }
    trap 'kill $(jobs -p) 2>/dev/null; restore' EXIT
    trap 'exit 0' TERM INT

    ring() {
      local s line snoozed=0
      for s in $(pactl list short sinks | cut -f2); do
        saved+=("$s $(pactl get-sink-volume "$s" | grep -o '[0-9]*%' | head -1) $(pactl get-sink-mute "$s" | cut -d' ' -f2)")
      done
      (
        while :; do
          for s in $(pactl list short sinks | cut -f2); do
            pactl set-sink-mute "$s" 0
            pactl set-sink-volume "$s" 100%
          done
          pw-play ${beep}
        done
      ) &
      coproc keys { exec libinput debug-events 2>/dev/null; }
      while (( $(ppm) >= threshold )); do
        if read -r -t 1 -u "''${keys[0]:-}" line 2>/dev/null; then
          [[ $line == *KEYBOARD_KEY*pressed* ]] && snoozed=1 && break
        elif (( $? <= 128 )); then
          sleep 1
        fi
      done
      kill $(jobs -p) 2>/dev/null
      wait
      restore
      (( snoozed )) && echo "snoozed" && sleep 1800
    }

    while :; do
      (( $(ppm) >= threshold )) && echo "CO2 $(ppm) ppm" && ring
      sleep 10
    done
  '';
in {
  options.dreaming.hardware.airco2ntrol = {
    enable = lib.mkEnableOption "TFA AirCO2ntrol Mini (04d9:a052) access and Prometheus textfile exporter";
    alarmPpm = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Beep at full volume while CO2 is at or above this level, until a key is pressed (30 min snooze).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.airco2ntrol-alarm = lib.mkIf (cfg.alarmPpm != null) {
      description = "Beep on high CO2";
      wantedBy = ["default.target"];
      after = ["pipewire.service"];
      path = [pkgs.coreutils pkgs.gnugrep pkgs.pulseaudio pkgs.pipewire pkgs.libinput];
      serviceConfig = {
        ExecStart = alarm;
        Restart = "always";
        RestartSec = 10;
      };
    };

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
