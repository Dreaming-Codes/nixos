{pkgs, ...}: {
  programs = {
    steam = {
      enable = true;
      package = pkgs.steam.override {
        # steamos3 fixes dualshock support while using proton wayland mode
        extraArgs = "-steamos3";
      };
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
