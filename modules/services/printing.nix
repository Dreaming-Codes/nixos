{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.services.printing;
in {
  options.dreaming.services.printing.enable =
    lib.mkEnableOption "CUPS printing"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    services.printing = {
      enable = true;
      drivers = [
        pkgs.hplipWithPlugin
      ];
    };
  };
}
