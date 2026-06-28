{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.core.boot;
in {
  options.dreaming.core.boot.enable =
    lib.mkEnableOption "core boot loader/console config (limine, terminus font)"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    boot = {
      loader.limine.enable = true;
      loader.efi.canTouchEfiVariables = true;
      consoleLogLevel = 0;
      initrd = {
        systemd.enable = true;
        verbose = false;
      };
      kernelParams = [
        "acpi_call"
        "quiet"
      ];
    };

    # Console font
    console = {
      earlySetup = true;
      font = "${pkgs.terminus_font}/share/consolefonts/ter-120n.psf.gz";
      packages = with pkgs; [terminus_font];
    };
  };
}
