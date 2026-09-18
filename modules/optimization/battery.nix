{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.optimization.battery;

  # Keep HID input and fingerprint readers out of USB autosuspend. powertop
  # enables autosuspend globally; without this, some boards drop input or the
  # fingerprint sensor stops responding on the lock screen.
  # Fingerprint vendors: EGIS (1c7a), Goodix (27c6), Synaptics (06cb), Validity (138a).
  keepUsbInputAwake = pkgs.writeShellScript "keep-usb-input-awake" ''
    for intf in /sys/bus/usb/devices/*:*/bInterfaceClass; do
      if [ -f "$intf" ] && [ "$(cat "$intf")" = "03" ]; then
        devpath="$(dirname "$intf")"
        parent="$(readlink -f "$devpath/..")"
        if [ -f "$parent/power/control" ]; then
          echo on > "$parent/power/control"
        fi
      fi
    done
    for dev in /sys/bus/usb/devices/*; do
      [ -f "$dev/idVendor" ] || continue
      vendor="$(cat "$dev/idVendor")"
      case "$vendor" in
        1c7a|27c6|06cb|138a)
          if [ -f "$dev/power/control" ]; then
            echo on > "$dev/power/control"
          fi
          ;;
      esac
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
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1c7a", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="06cb", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="138a", ATTR{power/control}="on"
    '';

    # Re-apply after powertop --auto-tune turns autosuspend on for everything.
    systemd.services.powertop.serviceConfig.ExecStartPost = "${keepUsbInputAwake}";
  };
}
