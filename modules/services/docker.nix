{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.services.docker;
in {
  options.dreaming.services.docker.enable =
    lib.mkEnableOption "Docker/container runtime"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      docker.enable = true;
      spiceUSBRedirection.enable = true;
    };

    environment.systemPackages = with pkgs; [
      oxker
    ];
  };
}
