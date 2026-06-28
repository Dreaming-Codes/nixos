{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.desktop.fonts;
in {
  options.dreaming.desktop.fonts.enable =
    lib.mkEnableOption "system fonts"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    fonts.packages = with pkgs; [
      ioskeley-mono.normal-NF
    ];
  };
}
