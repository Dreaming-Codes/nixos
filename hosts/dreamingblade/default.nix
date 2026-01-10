{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    ../../modules/programs/college.nix
  ];

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

  environment.systemPackages = with pkgs; [nrfutil];
  nixpkgs.config.segger-jlink.acceptLicense = true;

  home-manager.users.dreamingcodes = {
    wayland.windowManager.hyprland = {
      settings = {
        bindl = [
          ",switch:off:Lid Switch, exec, hyprlock --immediate"
        ];
        env = [
          "AQ_DRM_DEVICES,/dev/dri/card0:/dev/dri/card1"
        ];
        monitor = [
          "eDP-1, 1920x1080@60, 0x0, 1"
          "DP-2, 2560x1440@179.84, 1920x0, 1"
        ];
        workspace = [
          # Workspace names only - monitor bindings handled by dynamic-workspaces.sh
          "11, defaultName:F1"
          "12, defaultName:F2"
          "13, defaultName:F3"
          "14, defaultName:F4"
          "15, defaultName:F5"
          "16, defaultName:F6"
          "17, defaultName:F7"
          "18, defaultName:F8"
          "19, defaultName:F9"
          "20, defaultName:F10"
          "21, defaultName:F11"
          "22, defaultName:F12"
        ];
      };
    };

    # Dynamic workspace configuration daemon - listens to Hyprland IPC for monitor events
    systemd.user.services.dynamic-workspaces = {
      Unit = {
        Description = "Dynamic workspace configuration for Hyprland";
        PartOf = ["hyprland-session.target"];
        After = ["hyprland-session.target"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.writeShellScript "dynamic-workspaces" ''
          export PATH="${pkgs.socat}/bin:${pkgs.jq}/bin:${pkgs.hyprland}/bin:$PATH"
          ${builtins.readFile ../../scripts/dynamic-workspaces.sh}
        ''}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = ["hyprland-session.target"];
      };
    };
  };

  services.razer-laptop-control.enable = true;

  # Handle race condition: greeter starts daemon first, then exits when we log in.
  # Our session's daemon fails initially but retries after greeter's daemon stops.
  systemd.user.services.razerdaemon.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 2;
  };
  # Enable rocm support for the iGPU on the laptop
  nixpkgs.config.rocmSupport = true;
  # Enable cuda support for the dGPU on the laptop
  nixpkgs.config.cudaSupport = true;

  boot.kernelModules = ["kvm-amd"];
  # nvidia.NVreg_EnableGpuFirmware=0
  boot.kernelParams = ["nvidia.NVreg_PreserveVideoMemoryAllocations=1"];

  hardware.nvidia-container-toolkit.enable = true;

  ### Nvidia STUFF
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [
    "nvidia"
    "amdgpu"
  ];

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = false;

    # FIXME: revert to stable nvidia driver once https://github.com/nixos/nixpkgs/issues/467814 is fixed
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  hardware.keyboard.qmk.enable = true;
  services.udev.packages = with pkgs; [
    nrf-udev
    pkgs.keychron-udev-rules
  ];

  # Keychron Q6 Pro - grant hidraw access for VIA/QMK configurator
  services.udev.extraRules = ''
    # Keychron Q6 Pro - world read/write for WebHID browser access
    KERNEL=="hidraw*", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0660", MODE="0666", GROUP="plugdev", TAG+="uaccess"
    # Keychron Q6 Pro - disable USB autosuspend
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3434", ATTR{idProduct}=="0660", ATTR{power/control}="on"
  '';

  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    nvidiaBusId = "PCI:1:0:0";
    amdgpuBusId = "PCI:4:0:0";
  };

  specialisation = let
    # Base specialisations (without open/proprietary split)
    baseSpecialisations = {
      performance = {
        system.nixos.tags = ["performance"];
        hardware.nvidia = {
          powerManagement.finegrained = lib.mkForce false;
          prime.offload.enable = lib.mkForce false;
          prime.offload.enableOffloadCmd = lib.mkForce false;
          prime.sync.enable = lib.mkForce true;
        };
      };

      reverse = {
        system.nixos.tags = ["reverse"];
        hardware.nvidia = {
          powerManagement.finegrained = lib.mkForce false;
          prime.offload.enable = lib.mkForce false;
          prime.offload.enableOffloadCmd = lib.mkForce false;
          prime.sync.enable = lib.mkForce false;
          prime.reverseSync.enable = lib.mkForce true;
        };
      };
    };

    # Function to generate open/proprietary variants
    mkVariants = name: cfg: {
      "${name}-open".configuration =
        cfg
        // {
          system.nixos.tags = cfg.system.nixos.tags ++ ["open"];
          hardware.nvidia.open = lib.mkForce true;
        };
    };

    # Merge all generated variants
    generated = lib.foldl' lib.recursiveUpdate {} (lib.mapAttrsToList mkVariants baseSpecialisations);
  in
    generated
    // {
      # Keep no-gpu as is (no variants)
      no-gpu.configuration = {
        system.nixos.tags = ["no-gpu"];
        boot.extraModprobeConfig = ''
          blacklist nouveau
          options nouveau modeset=0
        '';
        services.udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
          ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
        '';
        boot.blacklistedKernelModules = [
          "nouveau"
          "nvidia"
          "nvidia_drm"
          "nvidia_modeset"
        ];
      };
    };
}
