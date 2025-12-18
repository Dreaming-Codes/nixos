{
  config,
  pkgs,
  lib,
  ...
}: let
  # Groups shared by all users
  commonGroups = [
    "networkmanager"
    "docker"
    "kvm"
    "adbusers"
    "input"
    "plugdev"
    "pipewire"
    "wireshark"
    "dialout"
    "flatpak"
  ];

  # Admin-only groups (sudo + libvirt system access)
  adminGroups = [
    "wheel"
    "libvirtd"
  ];
in {
  # Export groups for use in other modules (e.g., desktop.nix for riccardo)
  options.users.commonGroups = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = commonGroups;
    description = "Common groups shared by all users";
  };

  config = {
    # Ensure flatpak group exists even on systems without flatpak enabled
    users.groups.flatpak = {};

    security = {
      # auto unlock kwallet on boot
      pam = {
        services = {
          "dreamingcodes" = {
            kwallet = {
              enable = true;
              package = pkgs.kdePackages.kwallet-pam;
            };
          };
        };
      };
    };

    users.users.dreamingcodes = {
      isNormalUser = true;
      description = "DreamingCodes";
      extraGroups = commonGroups ++ adminGroups;
      shell = pkgs.fish;
    };
  };
}
