{
  config,
  lib,
  ...
}: {
  # Link-Local (APIPA) configuration for deterministic peer-to-peer over a dumb switch.
  # This tells NetworkManager that ANY ethernet connection should use DHCP for the
  # campus network (auto), but ALSO give itself a 169.254.x.x link-local IP and route.
  networking = {
    networkmanager.ensureProfiles.profiles = {
      "Campus Dumb Switch" = {
        connection = {
          id = "Campus Dumb Switch";
          type = "ethernet";
          autoconnect = true;
          "autoconnect-priority" = 10;
        };
        match = {
          # This applies the profile to ALL ethernet adapters (en* like enp4s0, eth* like eth0)
          name = "en*,eth*";
        };
        ipv4 = {
          # method=auto asks the campus for a standard IP via DHCP
          method = "auto";
          # We explicitly add the link-local route so it knows to send 169.254.x.x traffic out this adapter
          may-fail = false;
          route1 = "169.254.0.0/16";
        };
      };
    };

    # The firewall needs to allow traffic from the local link subnet (169.254.x.x)
    firewall = {
      extraCommands = ''
        # Accept all traffic from the 169.254.x.x subnet over ANY interface
        iptables -I INPUT -s 169.254.0.0/16 -j ACCEPT
      '';
    };
  };
}
