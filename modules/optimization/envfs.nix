{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.dreaming.optimization;
in {
  config = lib.mkIf cfg.envfs.enable {
    services.envfs = {
      enable = true;
      extraFallbackPathCommands = ''
        ln -s ${pkgs.bash}/bin/bash $out/bash
      '';
    };

    # Fix FUSE race condition where mount.envfs returns before the kernel
    # registers the mount, causing systemd to report "Failed to mount /usr/bin"
    # and the subsequent dep /bin
    fileSystems."/usr/bin".options = ["x-systemd.mount-timeout=10s"];
    fileSystems."/bin".options = ["x-systemd.mount-timeout=10s"];
  };
}
