{ config, pkgs, ... }: {
  networking.networkmanager.enable = true;

  networking.firewall = {
<<<<<<< Updated upstream
    allowedTCPPortRanges = [
        # KDE Connect
        {
        from = 1714;
        to = 1764;
=======
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
        },
        # chromecast
        {
            from = 32768;
            to = 60999;
>>>>>>> Stashed changes
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
