{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.hardware.graphics;
in {
  options.dreaming.hardware.graphics.enable =
    lib.mkEnableOption "graphics/GPU base config"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    hardware = {
      cpu = {
        amd.updateMicrocode = true;
        intel.updateMicrocode = true;
      };
      enableRedistributableFirmware = true;
      graphics = {
        enable = true;
        enable32Bit = true;
      };
    };
  };
}
