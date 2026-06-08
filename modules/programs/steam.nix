{pkgs, ...}: let
  steamos-session-select = pkgs.writeShellScriptBin "steamos-session-select" ''
    exec ${pkgs.steam}/bin/steam -shutdown "$@"
  '';
in {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession = {
      enable = true;
      steamArgs = [
        "-steamdeck"
      ];
      args = [
        "--mangoapp"
      ];
    };
    extraPackages = with pkgs; [
      mangohud
      steamos-session-select
    ];
    extest.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  environment.systemPackages = with pkgs; [steam-run];
}
