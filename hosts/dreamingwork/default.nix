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
  # x86_64 package set, only used to borrow app icons for the PWA launchers
  # (Slack/Discord ship no aarch64 build); their binaries are never executed.
  pkgsX86 = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
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
    [
      ../../modules/programs/asahi-x86.nix
      ../../modules/programs/pwa-apps.nix
    ]
    ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

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

  # iwd's EAP-TLS needs the kernel PKCS#8
  boot.kernelModules = ["pkcs8_key_parser"];

  # The CachyOS kernel is x86-only; Asahi ships its own kernel via the
  # apple-silicon-support module. Keep the rest of the optimization profile.
  dreamingoptimal.optimization.cachykernel.enable = lib.mkForce false;

  programs.asahi-x86.enable = false;

  # Slack and Discord can't run under FEX and ship no aarch64 build
  programs.pwaApps = {
    enable = true;
    apps = [
      {
        name = "slack";
        url = "https://app.slack.com/client";
        desktopName = "Slack";
        iconSource = pkgsX86.slack;
        categories = ["Network" "InstantMessaging"];
      }
      {
        name = "discord";
        url = "https://discord.com/app";
        desktopName = "Discord";
        iconSource = pkgsX86.discord;
        categories = ["Network" "InstantMessaging"];
      }
    ];
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
