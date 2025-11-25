{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports =
    [
      ./modules/networking.nix
      # ./modules/davinci-resolve.nix
      ./modules/services.nix
      ./modules/system.nix
      ./modules/user.nix
      ./modules/home-manager.nix
      ./modules/systemPrograms.nix
      ./misc/sdks.nix
      ./modules/steam.nix
      ./modules/optimization.nix
      ./modules/samba.nix
      ./modules/nix.nix
      ./modules/locales.nix
      ./modules/hardware.nix
      ./modules/boot.nix
      # ./modules/davinci.nix
    ]
    ++ (
      if builtins.pathExists /etc/nixos/secrets/github.nix
      then [/etc/nixos/secrets/github.nix]
      else []
    );
}
