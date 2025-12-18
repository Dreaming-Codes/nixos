{...}: {
  services.resolved.enable = true;
  networking = {
    useDHCP = false;
    wireless.enable = true;
    networkmanager = {
      enable = true;
      unmanaged = ["lo" "docker0" "virbr0"];
      dns = "systemd-resolved";
      wifi = {
        powersave = true;
        macAddress = "stable-ssid";
      };
    };
  };
  systemd.network.wait-online.enable = false;

  services.cloudflare-warp.enable = true;

  hardware.wirelessRegulatoryDatabase = true;

  networking.firewall = {
    allowedTCPPortRanges = [
      {
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
