{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.optimization.battery;
in {
  config = lib.mkIf cfg.enable {
    powerManagement.enable = true;

    boot.extraModprobeConfig = ''
      options snd_hda_intel power_save=1
    '';

    # Runtime PM for every PCI, USB and I2C device. HID input and fingerprint
    # readers stay awake: some boards drop input or the sensor stops
    # responding on the lock screen. Their rules come last so they win.
    # Fingerprint vendors: EGIS (1c7a), Goodix (27c6), Synaptics (06cb), Validity (138a).
    services.udev.extraRules = ''
      ACTION=="add|bind", SUBSYSTEM=="pci", TEST=="power/control", ATTR{power/control}="auto"
      ACTION=="add", SUBSYSTEM=="i2c", TEST=="power/control", ATTR{power/control}="auto"
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", TEST=="power/control", ATTR{power/control}="auto"

      ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", RUN+="${pkgs.bash}/bin/bash -c 'echo on > /sys$devpath/../power/control 2>/dev/null || true'"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1c7a", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="06cb", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="138a", ATTR{power/control}="on"
    '';
  };
}
