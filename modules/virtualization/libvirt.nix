{
  pkgs,
  inputs,
  config,
  lib,
  ...
}: let
  secureBootOVMF = pkgs.OVMF.override {
    secureBoot = true;
    # msVarsTemplate = true;
    tpmSupport = true;
    tlsSupport = true;
  };
in {
  imports = [
    inputs.nixos-vfio.nixosModules.vfio
    ./qemu
  ];

  # remove need for sudo auth when switching inputs
  security.sudo.extraRules = [
    {
      groups = ["libvirtd"];
      commands = [
        {
          command = "/run/current-system/sw/bin/ddcutil -d 2 setvcp 60 0x0f";
          options = ["SETENV" "NOPASSWD"];
        }
        {
          command = "/run/current-system/sw/bin/ddcutil -d 2 setvcp 60 0x11";
          options = ["SETENV" "NOPASSWD"];
        }
      ];
    }
  ];

  virtualisation.libvirtd = {
    enable = true;
    clearEmulationCapabilities = false;
    qemu = {
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [pkgs.OVMFFull.fd];
      };
      verbatimConfig = ''
        nvram = [
          "/run/libvirt/nix-ovmf/OVMF_VARS.fd"
        ]
      '';
    };
    deviceACL = [
      "/dev/null"
      "/dev/full"
      "/dev/zero"
      "/dev/random"
      "/dev/urandom"
      "/dev/ptmx"
      "/dev/kvm"
      "/dev/kqemu"
      "/dev/rtc"
      "/dev/hpet"
      "/dev/net/tun"
    ];
  };

  environment.etc = {
    spoofedOVMF = {
      source = secureBootOVMF.fd;
    };
  };

  environment.systemPackages = with pkgs; [
    python313Packages.virt-firmware
  ];
}
