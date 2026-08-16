{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.optimization.battery;

  # Keep HID input devices (keyboards/mice) out of USB autosuspend. powertop
  # enables autosuspend globally; without this, some boards drop or lag.
  keepHidAwake = pkgs.writeShellScript "keep-hid-usb-awake" ''
    for intf in /sys/bus/usb/devices/*:*/bInterfaceClass; do
      if [ -f "$intf" ] && [ "$(cat "$intf")" = "03" ]; then
        devpath="$(dirname "$intf")"
        parent="$(readlink -f "$devpath/..")"
        if [ -f "$parent/power/control" ]; then
          echo on > "$parent/power/control"
        fi
      fi
    done
  '';
in {
  config = lib.mkIf cfg.enable {
    powerManagement = {
      enable = true;
      powertop.enable = true;
    };

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", RUN+="${pkgs.bash}/bin/bash -c 'echo on > /sys$devpath/../power/control 2>/dev/null || true'"
    '';

    # Re-apply after powertop --auto-tune turns autosuspend on for everything.
    systemd.services.powertop.serviceConfig.ExecStartPost = "${keepHidAwake}";
  };
}
