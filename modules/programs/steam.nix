{pkgs, ...}: {
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
      gamescope
    ];
    extest.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  environment.systemPackages = with pkgs; [steam-run];
}
