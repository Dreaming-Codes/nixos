{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.games;
in {
  imports = [
    ./steam.nix
  ];

  options.dreaming.games.enable = lib.mkEnableOption "gaming feature group";

  config = lib.mkIf cfg.enable {
    dreaming.games.steam.enable = lib.mkDefault true;
  };
}
