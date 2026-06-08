{pkgs, ...}: let
  steamos-session-select = pkgs.writeShellScriptBin "steamos-session-select" ''
    exec ${pkgs.steam}/bin/steam -shutdown "$@"
  '';
in {
  programs = {
    gamescope = {
      enable = true;
      capSysNice = true;
      enableWsi = true;
    };
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      gamescopeSession = {
        enable = true;
        args = [
          "--mangoapp"
        ];
      };
      extest.enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    steam-run
    mangohud
    steamos-session-select
  ];
}
