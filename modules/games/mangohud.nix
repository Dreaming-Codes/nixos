{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.games.mangohud;
in {
  options.dreaming.games.mangohud.enable = lib.mkEnableOption "MangoHud performance overlay";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.mangohud];
  };
}
