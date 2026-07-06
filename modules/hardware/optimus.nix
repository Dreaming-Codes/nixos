{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.hardware.optimus;
in {
  options.dreaming.hardware.optimus = {
    enable = lib.mkEnableOption "NVIDIA Optimus hybrid GPU (PRIME offload + proprietary driver)";

    nvidiaBusId = lib.mkOption {
      type = lib.types.str;
      example = "PCI:1:0:0";
      description = "PCI bus ID of the NVIDIA dGPU (from lspci, format PCI:bus:device:function in decimal).";
    };

    # Exactly one of these should be set for hybrid PRIME setups.
    amdgpuBusId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "PCI:4:0:0";
      description = "PCI bus ID of the AMD iGPU, if present.";
    };

    intelBusId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "PCI:0:2:0";
      description = "PCI bus ID of the Intel iGPU, if present.";
    };

    open = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use the NVIDIA open kernel modules (Turing and newer).";
    };

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nixpkgs cudaSupport for packages that opt into CUDA.";
    };

    containerToolkit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the NVIDIA container toolkit (Docker/Podman GPU passthrough).";
    };

    specialisations = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install boot specialisations:
        - performance-open: PRIME sync (dGPU always on)
        - reverse-open: reverse PRIME sync
        - no-gpu: fully disable NVIDIA (power saving / troubleshooting)
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.amdgpuBusId != null || cfg.intelBusId != null;
          message = "dreaming.hardware.optimus: set amdgpuBusId and/or intelBusId for PRIME.";
        }
      ];

      # CUDA for the dGPU. Avoid global rocmSupport — no binary cache covers
      # rocm-tainted closures broadly, which forces local rebuilds of vtk/etc.
      nixpkgs.config.cudaSupport = lib.mkIf cfg.cudaSupport true;

      boot.kernelParams = ["nvidia.NVreg_PreserveVideoMemoryAllocations=1"];

      hardware.nvidia-container-toolkit.enable = cfg.containerToolkit;

      hardware.graphics.enable = true;

      # Load nvidia for Xorg/Wayland; also load amdgpu when the iGPU is AMD so
      # modesetting of the internal panel works under PRIME.
      services.xserver.videoDrivers =
        ["nvidia"]
        ++ lib.optional (cfg.amdgpuBusId != null) "amdgpu";

      hardware.nvidia = {
        modesetting.enable = true;

        # Save full VRAM across suspend (fixes corruption / crashes after wake).
        powerManagement.enable = true;

        # Fine-grained PM: power off the dGPU when idle (Turing+).
        powerManagement.finegrained = true;

        open = cfg.open;
        nvidiaSettings = false;
        package = config.boot.kernelPackages.nvidiaPackages.stable;

        prime = {
          offload = {
            enable = true;
            enableOffloadCmd = true;
          };
          nvidiaBusId = cfg.nvidiaBusId;
          amdgpuBusId = lib.mkIf (cfg.amdgpuBusId != null) cfg.amdgpuBusId;
          intelBusId = lib.mkIf (cfg.intelBusId != null) cfg.intelBusId;
        };
      };
    }

    (lib.mkIf cfg.specialisations {
      specialisation = let
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

        mkVariants = name: spec: {
          "${name}-open".configuration =
            spec
            // {
              system.nixos.tags = spec.system.nixos.tags ++ ["open"];
              hardware.nvidia.open = lib.mkForce true;
            };
        };

        generated = lib.foldl' lib.recursiveUpdate {} (lib.mapAttrsToList mkVariants baseSpecialisations);
      in
        generated
        // {
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
    })
  ]);
}
