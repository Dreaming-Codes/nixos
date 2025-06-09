{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    /etc/nixos/secrets/github.nix
    /etc/nixos/hardware-configuration.nix
    ./modules/networking.nix
    ./modules/services.nix
    ./modules/system.nix
    ./modules/user.nix
    ./modules/home-manager.nix
    ./modules/niri-config.nix
    ./modules/systemPrograms.nix
    ./misc/sdks.nix
    ./modules/steam.nix
    ./modules/optimization.nix
    ./modules/samba.nix
    ./modules/hypervisor-phantom.nix
    ./modules/virtualization
    ./modules/nix.nix
    ./modules/locales.nix
    ./modules/hardware.nix
    ./modules/boot.nix
  ];
}
