{...}: {
  # Intel AX210 WiFi optimizations - disable power saving for better stability
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=0
    options iwlmvm power_scheme=1
  '';

  # Use geoclue to automatically set regulatory domain based on location
  location.provider = "geoclue2";

  services.resolved = {
    enable = true;
    dnsovertls = "true";
  };
  networking = {
    nameservers = [
      "1.1.1.1#cloudflare-dns.com"
      "1.0.0.1#cloudflare-dns.com"
      "2606:4700:4700::1111#cloudflare-dns.com"
      "2606:4700:4700::1001#cloudflare-dns.com"
    ];
    useDHCP = false;
    dhcpcd.enable = false; # NetworkManager handles DHCP, don't run dhcpcd separately
    wireless = {
      enable = true;
      # Enterprise WiFi (eduroam/WPA-Enterprise) optimizations
      extraConfig = ''
        # More aggressive background scanning for better roaming
        # Format: bgscan="<module>:<short_interval>:<signal_threshold>:<long_interval>"
        # Scan every 15s when signal < -65dBm, otherwise every 120s
        bgscan="simple:15:-65:120"

        # Enable Opportunistic Key Caching for faster roaming
        okc=1

        # Enable Protected Management Frames (required by some enterprise networks)
        pmf=1

        # Faster reconnection
        fast_reauth=1

        # Roaming improvements
        # Only roam if new AP is at least 8dB better than current
        bss_transition=1

        # Prefer scanning current frequency first (faster roaming)
        scan_cur_freq=1

        # Auth timeout - default is 10s, Android uses 30s
        # 15s is a reasonable middle ground for enterprise networks
        auth_timeout=15
      '';
    };
    networkmanager = {
      enable = true;
      unmanaged = [
        "lo"
        "docker0"
        "virbr0"
      ];
      dns = "systemd-resolved";
      wifi = {
        powersave = false;
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
