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
    # No avahi: cups-browsed tracks services.avahi.enable and stays off.
    # Dense Bonjour LANs make avahi expensive; add printers by IP/IPP.
    services.printing = {
      enable = true;
      drivers = [
        pkgs.hplipWithPlugin
      ];
    };
  };
}
