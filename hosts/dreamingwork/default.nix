{
  inputs,
  lib,
  ...
}: let
  asahiPkgs = import inputs.apple-silicon.inputs.nixpkgs {
    localSystem.system = "aarch64-linux";
    crossSystem.system = "aarch64-linux";
    overlays = [
      inputs.apple-silicon.overlays.default
    ];
  };
in {
  # Apple Silicon work laptop running Asahi Linux (aarch64).
  # Installed via the upstream nixos-apple-silicon installer ISO; see
  # docs/asahi-x86-emulation.md for x86-only apps deferred to FEX/muvm.
  #
  # NOTE: hardware-configuration.nix is generated on the target with
  # `nixos-generate-config` after partitioning, then committed here.
  # The ./firmware dir (Asahi peripheral firmware copied off the EFI system
  # partition) is also produced at install time by scripts/asahi-install.sh.
  imports =
    lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  nixpkgs.hostPlatform = "aarch64-linux";

  # Flakes forbid the default impure reference to the firmware on the EFI
  # system partition. If scripts/asahi-install.sh has copied the firmware into
  # ./firmware, reference it purely; otherwise fall back to extracting it from
  # the EFI partition (works for non-flake / installer-time builds).
  hardware.asahi =
    {
      # Use nixos-apple-silicon's own pinned nixpkgs for the major Asahi
      # packages. Its Cachix is built for that input set; using the host
      # nixpkgs here causes cache misses and kernel builds during install.
      pkgs = lib.mkForce asahiPkgs;
    }
    // (
      if builtins.pathExists ./firmware
      then {peripheralFirmwareDirectory = ./firmware;}
      else {extractPeripheralFirmware = true;}
    );

  # Asahi/U-Boot UEFI boot: systemd-boot, and never touch EFI variables.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # Broadcom WiFi on Apple hardware needs iwd (WPA3 unsupported by wpa_supplicant
  # on these chips). This implicitly enables iwd and disables wpa_supplicant.
  networking.networkmanager.wifi.backend = "iwd";

  # The CachyOS kernel is x86-only; Asahi ships its own kernel via the
  # apple-silicon-support module. Keep the rest of the optimization profile.
  dreamingoptimal.optimization.cachykernel.enable = lib.mkForce false;

  # Some MacBooks render graphical sessions on the touchbar without this.
  # Safe to leave enabled on models without a touchbar.
  hardware.apple.touchBar = {
    enable = true;
  };

  home-manager.users.dreamingcodes = {
    home.file.".config/niri/dms/host-local.kdl" = {
      source = ../../config/niri/dms/host-dreamingwork.kdl;
      force = true;
    };

    wayland.windowManager.hyprland.settings.input.touchpad = {
      tap-to-click = true;
      tap_button_map = "lrm";
      clickfinger_behavior = false;
      natural_scroll = true;
    };
  };

  # Asahi binary cache (host-local; avoids building the kernel locally).
  nix.settings = {
    extra-substituters = [
      "https://nixos-apple-silicon.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
    ];
  };
}
