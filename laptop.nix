{
  pkgs,
  lib,
  config,
  ...
}: {
  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "usb_storage" "usbhid" "sd_mod"];
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/0806bf06-5970-44da-8b99-400c140db160";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/3E30-ADDD";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
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
          "DP-2, 2560x1440@179.84, 0x0, 1"
          "eDP-1, 1920x1080@60, 0x1440, 1"
        ];
      };
    };
  };

  services.razer-laptop-control.enable = true;
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
  services.xserver.videoDrivers = ["nvidia" "amdgpu"];

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

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  services.udev.packages = with pkgs; [
    nrf-udev
  ];

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

      # "${name}-proprietary".configuration =
      #   cfg
      #   // {
      #     system.nixos.tags = cfg.system.nixos.tags ++ ["proprietary"];
      #     hardware.nvidia.open = lib.mkForce false;
      #   };
    };

    # Merge all generated variants
    generated = lib.foldl' lib.recursiveUpdate {} (
      lib.mapAttrsToList mkVariants baseSpecialisations
    );
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
        boot.blacklistedKernelModules = ["nouveau" "nvidia" "nvidia_drm" "nvidia_modeset"];
      };
      # # Default proprietary variant (since base system is open by default)
      # default-proprietary.configuration = {
      #   system.nixos.tags = ["default" "proprietary"];
      #   hardware.nvidia.open = lib.mkForce false;
      # };
    };
}
