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

  # NixOS wireplumber already sets this; we re-apply after UnsetEnvironment.
  wpDataDirs = config.systemd.user.services.wireplumber.environment.XDG_DATA_DIRS or "";
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
      {
        assertion = wpDataDirs != "";
        message = "dreaming.hardware.galaxybook6-camera: wireplumber XDG_DATA_DIRS is empty";
      }
    ];

    boot.extraModulePackages = [modules];
    boot.kernelModules = ["ipu_bridge" "sc200pc"];

    environment.systemPackages = [
      pkgs.libcamera
      userspace
    ];
    environment.sessionVariables.LIBCAMERA_IPA_CONFIG_PATH = ipaConfigPath;

    # PipeWire libcamera path for browsers:
    # 1) Stock wireplumber.service sets MemoryDenyWriteExecute=yes, which
    #    prevents spa-libcamera from creating Video/Source nodes.
    # 2) The user manager's long XDG_DATA_DIRS must be cleared and replaced
    #    with the unit value, or libcamera monitor ends up with no sources
    #    even when cam(1) works.
    systemd.user.services.wireplumber = {
      serviceConfig = {
        MemoryDenyWriteExecute = lib.mkForce "no";
        UnsetEnvironment = ["XDG_DATA_DIRS"];
        Environment = lib.mkAfter [
          "XDG_DATA_DIRS=${wpDataDirs}"
          "LIBCAMERA_IPA_CONFIG_PATH=${ipaConfigPath}"
        ];
      };
    };

    # Hide raw IPU7 ISYS Bayer nodes from the V4L2 monitor. Capture is the
    # libcamera "Built-in Front Camera" source.
    services.pipewire.wireplumber.extraConfig."50-ipu7-hide-v4l2" = {
      "monitor.v4l2.rules" = [
        {
          matches = [
            {"api.v4l2.cap.driver" = "isys";}
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
