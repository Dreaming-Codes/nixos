{
  pkgs,
  lib,
  config,
  nix-index-database,
  inputs,
  ...
}: {
  imports = [
    ../../modules/desktop/sddm
  ];

  # Riccardo user (desktop only)
  users.users.riccardo = {
    isNormalUser = true;
    description = "Riccardo";
    extraGroups = config.users.commonGroups;
    shell = pkgs.fish;
  };

  # PAM kwallet for riccardo
  security.pam.services."riccardo" = {
    kwallet = {
      enable = true;
      package = pkgs.kdePackages.kwallet-pam;
    };
  };

  # Flatpak + Discover integration (desktop only)
  services.flatpak.enable = true;
  services.packagekit.enable = true;

  # Flatpak auto-update (system-wide)
  systemd.services.flatpak-update = {
    description = "Update Flatpak packages (system)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.flatpak}/bin/flatpak update -y";
    };
  };

  # Flatpak auto-update (user)
  systemd.user.services.flatpak-update-user = {
    description = "Update Flatpak packages (user)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.flatpak}/bin/flatpak update -y --user";
    };
  };

  systemd.user.timers.flatpak-update-user = {
    description = "Auto-update Flatpak packages (user)";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  systemd.timers.flatpak-update = {
    description = "Auto-update Flatpak packages";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Riccardo Home Manager configuration
  home-manager.users.riccardo = {
    imports = [
      nix-index-database.homeModules.nix-index
      ../../home/common.nix
    ];
    home.stateVersion = "24.11";
  };

  environment.systemPackages = with pkgs; [
    # amd gpu utility
    lact
    # amd encoders/decoders
    amf
    via
  ];

  boot.kernelModules = ["kvm-intel"];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/059dc105-5a7a-4c4c-967c-af7bc6c7dd1a";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/FF73-5BE2";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.sunshine = {
    enable = true;
    autoStart = false;
    capSysAdmin = true;
    openFirewall = true;
  };

  home-manager.users.dreamingcodes = {
    wayland.windowManager.hyprland = {
      settings = {
        monitor = [
          "HDMI-A-1, highres, 0x0, 1"
          "DP-1, 3440x1440@144, 1920x0, 1"
          "DP-2, highres, 5360x0, 1"
        ];
        workspace = [
          "1, default:true, monitor:DP-1"
          "2, monitor:DP-1"
          "3, monitor:DP-1"
          "4, monitor:DP-1"
          "5, monitor:DP-1"
          "6, monitor:DP-1"
          "7, monitor:DP-1"
          "8, monitor:DP-1"
          "9, monitor:DP-1"
          "10, monitor:DP-1"
          "11, defaultName:F1, default:true, monitor:DP-2"
          "12, defaultName:F2, monitor:DP-2"
          "13, defaultName:F3, monitor:DP-2"
          "14, defaultName:F4, monitor:DP-2"
          "15, defaultName:F5, monitor:DP-2"
          "16, defaultName:F6, monitor:DP-2"
          "17, defaultName:F7, monitor:DP-2"
          "18, defaultName:F8, monitor:DP-2"
          "19, defaultName:F9, monitor:DP-2"
          "20, defaultName:F10, monitor:DP-2"
          "21, defaultName:F11, monitor:DP-2"
          "22, defaultName:F12, monitor:DP-2"
          "23, defaultName:ALT1, default:true, monitor:HDMI-A-1"
          "24, defaultName:ALT2, monitor:HDMI-A-1"
          "25, defaultName:ALT3, monitor:HDMI-A-1"
          "26, defaultName:ALT4, monitor:HDMI-A-1"
          "27, defaultName:ALT5, monitor:HDMI-A-1"
          "28, defaultName:ALT6, monitor:HDMI-A-1"
          "29, defaultName:ALT7, monitor:HDMI-A-1"
          "30, defaultName:ALT8, monitor:HDMI-A-1"
          "31, defaultName:ALT9, monitor:HDMI-A-1"
          "32, defaultName:ALT10, monitor:HDMI-A-1"
        ];
      };
    };
  };

  # Additional kernel modules needed for virtualization
  boot.initrd.availableKernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
    "ahci"
    "usb_storage"
    "sd_mod"
    "amdgpu"
  ];
  # Blacklist nvidia gpu driver to prevent use
  boot.blacklistedKernelModules = ["nouveau" "nvidia"];

  nixpkgs.config.rocmSupport = true;

  hardware.graphics = {
    # Mesa
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [rocmPackages.clr.icd amf];
  };

  environment.variables = {
    # always prefer radv
    AMD_VULKAN_ICD = "RADV";
  };

  systemd.services.lact = {
    description = "AMDGPU Control Daemon";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {ExecStart = "${pkgs.lact}/bin/lact daemon";};
    enable = true;
  };

  # Fix for AMDGPU - Disabled cause it fails to build as of 30/01/2025
  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [rocblas hipblas clr];
    };
  in [
    "L+    /opt/rocm   -    -    -     -    ${rocmEnv}"
    # Allow dreamingcodes full access to riccardo's home via ACL
    "A+ /home/riccardo - - - - u:dreamingcodes:rwx"
    "A+ /home/riccardo - - - - d:u:dreamingcodes:rwx"
  ];

  hardware.keyboard.qmk.enable = true;
  services.udev.packages = [pkgs.via];
  # 1. fix suspend
  # 2. make xremap work
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x06ed", ATTR{power/wakeup}="disabled"
    KERNEL=="uinput", GROUP="input", TAG+="uaccess"
    SUBSYSTEM=="input", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0660", MODE="0660", TAG+="uaccess"
  '';

  boot.kernelParams = [
    "pcie_acs_override=downstream"
    "intel_iommu=on"
    "iommu=pt"
    "amdgpu.ppfeaturemask=0xFFF7FFFF"
    ''vfio-pci.ids="10de:1b81,10de:10f0"''
  ];
}
