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
  # networking.useNetworkd = false;
  systemd.network.wait-online.enable = false;

  services.cloudflare-warp.enable = true;

  hardware.wirelessRegulatoryDatabase = true;

  boot.kernelModules = ["tcp_bbr"];
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_fin_timeout" = 5;
  };

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
