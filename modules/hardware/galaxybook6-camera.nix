{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.dreaming.hardware.galaxybook6-camera;
  modules = config.boot.kernelPackages.callPackage (self + "/packages/galaxybook6-camera") {};
  userspace = pkgs.callPackage (self + "/packages/galaxybook6-camera/userspace.nix") {};
  ipaConfigPath = "${userspace}/share/libcamera/ipa";
in {
  options.dreaming.hardware.galaxybook6-camera = {
    enable = lib.mkEnableOption ''
      Samsung Galaxy Book6 Ultra built-in camera (IPU7 + SC200PC / ACPI SSLC2000).
      Loads OOT sc200pc + ipu-bridge SSLC2000, libcamera soft-ISP tuning, and
      exposes the camera through PipeWire for browsers.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.pipewire.wireplumber.enable;
        message = "dreaming.hardware.galaxybook6-camera requires services.pipewire.wireplumber.enable";
      }
    ];

    boot.extraModulePackages = [modules];
    boot.kernelModules = ["ipu_bridge" "sc200pc"];

    environment.systemPackages = [
      pkgs.libcamera
      userspace
    ];
    environment.sessionVariables.LIBCAMERA_IPA_CONFIG_PATH = ipaConfigPath;

    # Stock wireplumber.service sets MemoryDenyWriteExecute=yes, which
    # prevents spa-libcamera from creating Video/Source nodes.
    systemd.user.services.wireplumber = {
      environment.LIBCAMERA_IPA_CONFIG_PATH = ipaConfigPath;
      serviceConfig.MemoryDenyWriteExecute = lib.mkForce "no";
    };

    # Hide raw IPU7 ISYS Bayer nodes from the V4L2 monitor. Capture is the
    # libcamera "Built-in Front Camera" source. api.v4l2.cap.* is not yet
    # populated when device rules run, so match the PCI path.
    services.pipewire.wireplumber.extraConfig."50-ipu7-hide-v4l2" = {
      "monitor.v4l2.rules" = [
        {
          matches = [
            {"device.name" = "~v4l2_device.pci-0000_00_05.0*";}
          ];
          actions = {
            update-props = {
              "device.disabled" = true;
            };
          };
        }
      ];
    };
  };
}
