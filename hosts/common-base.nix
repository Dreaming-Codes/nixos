{...}: {
  # All feature modules are imported for every nixos host via easy-hosts
  # (flake-modules/hosts.nix, perClass "nixos"). This file only selects features
  # via dreaming.* toggles and sets the few unconditional shared settings.

  # Timezone and locale (common to all hosts)
  services.automatic-timezoned.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";

  # Use Cloudflare-based geolocation service
  services.geoclue2 = {
    enable = true;
    geoProviderUrl = "https://cloudflare-location-service.dreamingcodes.workers.dev/";
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  dreaming.optimization.enable = true;
  # The cache turns on per host once secrets/nbh-cache-<host>.yaml exists.
  dreaming.services.nbh = {
    enable = true;
    aws = {
      account = "845087560967";
      region = "eu-north-1";
    };
    cache = {
      bucket = "nbh-cache-845087560967";
      publicKey = "nbh-cache-845087560967-1:ncBMB14sruhdtGhlkrHt3tLw8xGBwq33QiQUM/760Rc=";
    };
  };

  dreaming.nixFileOverlay = {
    enable = true;
    systemRepoPath = "/home/dreamingcodes/.nixos";
    users = ["dreamingcodes"];
  };

  # Ensure geoclue starts after wpa_supplicant to reduce WiFi scan race condition.
  systemd.services.geoclue = {
    after = ["wpa_supplicant.service"];
    wants = ["wpa_supplicant.service"];
  };

  # State version
  system.stateVersion = "26.05";

  # Disable NixOS options documentation to avoid builtins.toFile warnings from NUR
  documentation.nixos.enable = false;
  documentation.doc.enable = false;
}
