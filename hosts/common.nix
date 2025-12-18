{
  config,
  pkgs,
  inputs,
  ...
}: {
  nixpkgs.overlays = [inputs.nix-cachyos-kernel.overlays.default];

  imports =
    [
      ../modules/core/boot.nix
      ../modules/core/networking.nix
      ../modules/core/nix.nix
      ../modules/core/security.nix
      ../modules/hardware/audio.nix
      ../modules/hardware/graphics.nix
      ../modules/hardware/optimization.nix
      ../modules/desktop/hyprland.nix
      ../modules/desktop/fonts.nix
      ../modules/desktop/xdg.nix
      ../modules/services/docker.nix
      ../modules/services/printing.nix
      ../modules/services/samba.nix
      ../modules/services/auto-update.nix
      ../modules/programs/steam.nix
      ../modules/programs/development.nix
      ../modules/programs/packages.nix
      ../modules/users/dreamingcodes.nix
    ]
    ++ (
      if builtins.pathExists /etc/nixos/secrets/github.nix
      then [/etc/nixos/secrets/github.nix]
      else []
    );

  # Timezone and locale (common to all hosts)
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # State version
  system.stateVersion = "24.11";
}
