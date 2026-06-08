{pkgs, ...}: {
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };
  };

  environment.variables = {
    PROTON_ENABLE_WAYLAND = "1";
  };

  environment.systemPackages = with pkgs; [
    steam-run
    mangohud
  ];
}
