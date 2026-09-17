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
      initrd.systemd.enable = true;
      kernelParams = [
        "acpi_call"
      ];
      plymouth = {
        enable = true;
        theme = "connect";
        themePackages = [
          (pkgs.adi1090x-plymouth-themes.override {
            selected_themes = ["connect"];
          })
        ];
      };
    };

    # Console font
    console = {
      earlySetup = true;
      font = "${pkgs.terminus_font}/share/consolefonts/ter-120n.psf.gz";
      packages = with pkgs; [terminus_font];
    };
  };
}
