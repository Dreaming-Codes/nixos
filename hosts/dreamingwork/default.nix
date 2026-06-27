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
  # Machine-local private NixOS settings (internal binary cache + CA trust)
  # live OUTSIDE this public repo so their URLs/keys/certs are never committed.
  # Reading this absolute path requires building with `--impure`.
  localNixSettingsPath = "/home/dreamingcodes/.config/nixos-local/local-nix-settings.nix";
  hasLocalNixSettings = builtins.pathExists localNixSettingsPath;
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
      ../../modules/programs/pwa-apps.nix
    ]
    ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix
    ++ lib.optional hasLocalNixSettings (import localNixSettingsPath);

  # Require the machine-local settings on this machine. If the file is missing,
  # fail loudly rather than silently building without the internal cache/CA.
  # NOTE: reading the local file requires `--impure`; without it the path is
  # not visible and this assertion will trip, which is the intended signal.
  assertions = [
    {
      assertion = hasLocalNixSettings;
      message = ''
        Expected local Nix settings at ${localNixSettingsPath} but it was not found.

        This file holds machine-local private NixOS settings (internal binary
        cache + Neuralink Internal Root CA), kept outside the public flake.
        Restore it, then rebuild with `--impure`, e.g.:

          nh os switch -- --impure
      '';
    }
  ];

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

  services.tailscale.enable = true;

  # Broadcom WiFi on Apple hardware needs iwd (WPA3 unsupported by wpa_supplicant
  # on these chips). This implicitly enables iwd and disables wpa_supplicant.
  networking.networkmanager.wifi.backend = "iwd";

  networking.networkmanager.settings.main.iwd-config-path = "/var/lib/iwd";

  # iwd's EAP-TLS needs the kernel PKCS#8
  boot.kernelModules = ["pkcs8_key_parser"];

  # The CachyOS kernel is x86-only; Asahi ships its own kernel via the
  # apple-silicon-support module. Keep the rest of the optimization profile.
  dreamingoptimal.optimization.cachykernel.enable = lib.mkForce false;

  # Slack and Discord can't run under FEX and ship no aarch64 build
  programs.pwaApps = {
    enable = true;
    apps = [
      {
        name = "slack";
        url = "https://app.slack.com/client";
        desktopName = "Slack";
        iconFile = builtins.fetchurl {
          url = "https://upload.wikimedia.org/wikipedia/commons/d/d5/Slack_icon_2019.svg";
          sha256 = "sha256-FxYEd6R1FmrQVW4AKOOwvQY01wwC57kgwEpEKeoYSrM=";
        };
        categories = [
          "Network"
          "InstantMessaging"
        ];
      }
      {
        name = "discord";
        url = "https://discord.com/app";
        desktopName = "Discord";
        iconFile = builtins.fetchurl {
          url = "https://upload.wikimedia.org/wikipedia/fr/4/4f/Discord_Logo_sans_texte.svg";
          sha256 = "sha256-fyh2K4xqb/xx1G9CocFagRLLtSu/x7jze5wITjEiTvk=";
        };
        categories = [
          "Network"
          "InstantMessaging"
        ];
      }
    ];
  };

  home-manager.users.dreamingcodes = {
    home.file.".config/niri/dms/host-local.kdl" = {
      source = ../../config/niri/dms/host-dreamingwork.kdl;
      force = true;
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
