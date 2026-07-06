{
  inputs,
  self,
  pkgs,
  lib,
  config,
  ...
}: let
  razer-energy = pkgs.writeShellScriptBin "razer-energy" (
    builtins.readFile "${self}/scripts/razer-energy.sh"
  );
  razer-laptop-control =
    inputs.razer-laptop-controller.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
    (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace Cargo.toml \
            --replace-fail 'features = ["linux-native"]' 'features = ["linux-static-hidraw"]'
        '';
    });
in {
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/0806bf06-5970-44da-8b99-400c140db160";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/3E30-ADDD";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  environment.systemPackages = [
    pkgs.nrfutil
    razer-energy
  ];
  nixpkgs.config.segger-jlink.acceptLicense = true;

  # howdy (IR scanner)
  services = {
    howdy = {
      enable = true;
      settings.video.dark_threshold = 90;
    };
    linux-enable-ir-emitter.enable = true;
  };
  security.pam.howdy.enable = true;
  security.pam.services.login.howdy.enable = false;
  security.pam.services.greetd.howdy.enable = false;
  security.pam.services.dms-greeter.howdy.enable = false;
  security.pam.services.dankshell = {};
  security.pam.services.dankshell.rules.auth.howdy.control = lib.mkForce "sufficient";
  security.pam.services.dankshell.rules.auth.howdy.order = lib.mkForce 13000;

  services.razer-laptop-control = {
    enable = true;
    package = razer-laptop-control;
  };

  # Only start in a graphical session, not in the greeter or linger manager
  systemd.user.services.razerdaemon = {
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    wantedBy = lib.mkForce ["graphical-session.target"];
    unitConfig = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    serviceConfig = {
      ExecStartPre = lib.mkBefore [
        "-${pkgs.coreutils}/bin/rm -f /tmp/razercontrol-socket"
      ];
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 5;
    };
  };
  boot.kernelModules = ["kvm-amd"];

  # Hybrid AMD iGPU + NVIDIA dGPU (see modules/hardware/optimus.nix).
  dreaming.hardware.optimus = {
    enable = true;
    nvidiaBusId = "PCI:1:0:0";
    amdgpuBusId = "PCI:4:0:0";
  };

  hardware.keyboard.qmk.enable = true;
  services.udev.packages = with pkgs; [
    nrf-udev
    pkgs.keychron-udev-rules
  ];

  # Keychron Q6 Pro - grant hidraw access for VIA/QMK configurator
  # Keychron Q6 Pro udev rules
  services.udev.extraRules = ''
    # Keychron Q6 Pro - world read/write for WebHID browser access
    KERNEL=="hidraw*", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0660", MODE="0666", GROUP="plugdev", TAG+="uaccess"
    # Disable USB autosuspend for all HID input devices (keyboards, mice, etc.)
    # When an interface with HID class (03) is added, walk up to the parent usb_device and disable autosuspend
    ACTION=="add", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", RUN+="${pkgs.bash}/bin/bash -c 'echo on > /sys$devpath/../power/control 2>/dev/null || true'"
    # Saleae Logic analyzers
    SUBSYSTEM=="usb", ATTR{idVendor}=="0925", ATTR{idProduct}=="3881", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="21a9", MODE="0666"
  '';

  # Disable USB autosuspend for all HID input devices at boot (runs after powertop which enables autosuspend)
  # Re-disable USB autosuspend for HID input devices after powertop enables it globally
  systemd.services.powertop.serviceConfig.ExecStartPost = "${pkgs.bash}/bin/bash -c 'for intf in /sys/bus/usb/devices/*:*/bInterfaceClass; do if [ -f \"$intf\" ] && [ \"$(cat \"$intf\")\" = \"03\" ]; then devpath=\"$(dirname \"$intf\")\"; parent=\"$(readlink -f \"$devpath/..\")\"; if [ -f \"$parent/power/control\" ]; then echo on > \"$parent/power/control\"; fi; fi; done'";
}
