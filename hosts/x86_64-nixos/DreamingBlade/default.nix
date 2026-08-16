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
      # Either face or password is enough (not 2FA).
      control = "sufficient";
      settings.video.dark_threshold = 90;
    };
    linux-enable-ir-emitter.enable = true;
  };
  security.pam.howdy.enable = true;
  # Boot/login: password only (no biometrics). Face is useless/harmful at greeter
  # with fscrypt home
  security.pam.services.login.howdy.enable = false;
  security.pam.services.greetd.howdy.enable = false;
  security.pam.services.dms-greeter.howdy.enable = false;
  # Screen lock: keep howdy at its default auto-order
  security.pam.services.dankshell = {};

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

  # Keychron Q6 Pro + Saleae (HID autosuspend fix lives in dreaming.optimization.battery)
  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0660", MODE="0666", GROUP="plugdev", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0925", ATTR{idProduct}=="3881", MODE="0666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="21a9", MODE="0666"
  '';
}
