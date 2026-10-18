{
  pkgs,
  config,
  lib,
  self,
  ...
}: let
  cfg = config.dreaming.core.boot;
  theme = pkgs.callPackage (self + "/packages/plymouth-neuralink") {};
in {
  options.dreaming.core.boot = {
    enable =
      lib.mkEnableOption "core boot loader/console config (limine, terminus font)"
      // {
        default = true;
      };
    aspect = lib.mkOption {
      type = lib.types.enum ["16x10" "16x9"];
      default = "16x10";
      description = "Panel aspect ratio, selects the matching Limine wallpaper.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      loader.limine = {
        enable = true;
        style = {
          wallpapers = ["${theme.limine}/neuralink-${cfg.aspect}.png"];
          wallpaperStyle = "stretched";
          backdrop = "000000";
          interface = {
            branding = "SELECT LINK TARGET";
            brandingColor = "9EE0FF";
            helpHidden = true;
            helpColor = "6FA6BE";
            helpColorBright = "FFFFFF";
          };
          graphicalTerminal = {
            font.spacing = 2;
            foreground = "C8DCE6";
            brightForeground = "FFFFFF";
            background = "FF000000";
            palette = "000000;FF6B6B;7FD8E0;D8E6EC;5C8FA8;A8C8FF;9EE0FF;8FA3AD";
            brightPalette = "3A4A52;FF9090;B0F0F8;FFFFFF;8FC4DC;C8DCFF;C8F0FF;FFFFFF";
            margin = 0;
            marginGradient = 0;
          };
        };
      };
      loader.efi.canTouchEfiVariables = true;
      initrd.systemd.enable = true;
      kernelParams = [
        "acpi_call"
      ];
      plymouth = {
        enable = true;
        theme = "neuralink";
        font = "${pkgs.ioskeley-mono.nf}/share/fonts/truetype/IoskeleyMonoNerdFontMono-Regular.ttf";
        themePackages = [theme];
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
