{ config, pkgs, ... }: {
  networking.networkmanager.enable = true;

  networking.firewall = {
    allowedTCPPortRanges = [{
      from = 1714;
      to = 1764;
    } # KDE Connect
      ];
    allowedUDPPortRanges = [
      # KDE Connect
      {
        from = 1714;
        to = 1764;
      }
      # chromecast
      {
        from = 32768;
        to = 60999;
      }
    ];
  };
}
