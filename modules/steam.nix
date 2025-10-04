{
  config,
  pkgs,
  ...
}: {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = false;
  };
  hardware.xpadneo.enable = true;

  environment.systemPackages = with pkgs; [steam-run];
}
