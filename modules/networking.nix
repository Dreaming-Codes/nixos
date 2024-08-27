{ config, pkgs, ... }: {
  networking.networkmanager.enable = true;

  networking.firewall = {
    allowedTCPPortRanges = [
        # KDE Connect
        {
        from = 1714;
        to = 1764;
        }
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
