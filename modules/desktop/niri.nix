{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.desktop.niri;
in {
  options.dreaming.desktop.niri.enable =
    lib.mkEnableOption "Niri compositor + DankMaterialShell"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    programs.niri = {
      enable = true;
      useNautilus = false;
    };

    environment.systemPackages = with pkgs; [
      niri
      niriswitcher
      xwayland-satellite
    ];
  };
}
