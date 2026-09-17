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
        theme = "catppuccin-macchiato";
        font = "${pkgs.ioskeley-mono.normal-NF}/share/fonts/truetype/IoskeleyMonoNerdFont-Regular.ttf";
        themePackages = [
          (pkgs.runCommand "catppuccin-plymouth-ioskeley" {} ''
            mkdir -p $out/share/plymouth/themes
            cp -a ${pkgs.catppuccin-plymouth}/share/plymouth/themes/catppuccin-macchiato \
              $out/share/plymouth/themes/
            substituteInPlace \
              $out/share/plymouth/themes/catppuccin-macchiato/catppuccin-macchiato.plymouth \
              --replace-fail "Font=Noto Sans 12" "Font=IoskeleyMono Nerd Font 12" \
              --replace-fail "TitleFont=Noto Sans Light 30" "TitleFont=IoskeleyMono Nerd Font 30"
          '')
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
