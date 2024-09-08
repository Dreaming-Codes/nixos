{ config, pkgs, inputs, ... }: {
  imports = [
    /etc/nixos/hardware-configuration.nix
    ./modules/networking.nix
    ./modules/services.nix
    ./modules/system.nix
    ./modules/user.nix
    ./modules/home-manager.nix
    ./modules/systemPrograms.nix
    ./misc/sdks.nix
    ./modules/steam.nix
    ./modules/optimization.nix
    ./modules/samba.nix
  ];
}
