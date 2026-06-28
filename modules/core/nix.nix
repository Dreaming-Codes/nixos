{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  # Single source of truth: ../../nixConfig.nix (also used by flake.nix's
  # nixConfig and flake-modules/devshell.nix).
  flakeNixConfig = import ../../nixConfig.nix;
  determinateNixPackages = inputs.determinate.inputs.nix.packages.${pkgs.stdenv.hostPlatform.system};
  emptySentryNative = pkgs.runCommand "empty-sentry-native" {} ''
    mkdir -p $out/bin $out/lib/debug
  '';
  determinateNixNoSentry = determinateNixPackages.nix.override {
    sentry-native = emptySentryNative;
    nix-cli = determinateNixPackages.nix-cli.overrideAttrs (old: {
      buildInputs = lib.filter (pkg: (pkg.pname or pkg.name or "") != "sentry-native") (
        old.buildInputs or []
      );
      mesonFlags =
        lib.filter (flag: !(lib.hasPrefix "-Dcrashpad-handler=" flag) && flag != "-Dsentry=enabled") (
          old.mesonFlags or []
        )
        ++ ["-Dsentry=disabled"];
    });
  };
in {
  nix = rec {
    # Channels are dead, long live flakes
    channel.enable = false;

    # Make builds run with low priority so my system stays responsive
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";

    # Do garbage collections whenever there is less than 3GB free space left
    extraOptions = ''
      max-free = ${toString (1024 * 1024 * 1024)}
      min-free = ${toString (100 * 1024 * 1024)}
    '';

    settings = {
      # Enable parallel evaluation (Determinate Nix 3.11+)
      eval-cores = 0;

      # Allow using flakes & automatically optimize the nix store
      auto-optimise-store = true;

      # Use available binary caches, this is not Gentoo
      # this also allows us to use remote builders to reduce build times and batter usage
      builders-use-substitutes = true;

      # Binary caches (system-level, no per-invocation prompt needed).
      # Source of truth: flake.nix nixConfig (re-used here).
      substituters = flakeNixConfig.substituters;
      # trusted-public-keys replaces (does not extend), so we must include the
      # default nixos cache key alongside the flake's extra-trusted-public-keys.
      trusted-public-keys =
        [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ]
        ++ flakeNixConfig.extra-trusted-public-keys;

      # We are using flakes, so enable the experimental features
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Users allowed to use Nix
      allowed-users = [
        "@wheel"
        "@nix"
      ];
      trusted-users = ["@wheel"];

      # Max number of parallel jobs
      max-jobs = "auto";

      # https://github.com/NixOS/nix/issues/8890#issuecomment-1703988345
      nix-path = nixPath;

      # Relax sandbox to allow DMI access for QEMU spoofing
      sandbox = "relaxed";

      connect-timeout = 3;
      fallback = true;
    };

    # Make legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    package = lib.mkForce determinateNixNoSentry;

    # Automtaically pin registries based on inputs
    registry = lib.mapAttrs (_: v: {flake = v;}) inputs;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Standard SSL cert location for precompiled binaries
  environment.variables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NIX_SENTRY_ENDPOINT = "";
    DETSYS_IDS_TELEMETRY = "disabled";
  };

  # Print a diff when running system updates
  system.activationScripts.diff = ''
    if [[ -e /run/current-system ]]; then
      (
        for i in {1..3}; do
          result=$(${config.nix.package}/bin/nix store diff-closures /run/current-system "$systemConfig" 2>&1)
          if [ $? -eq 0 ]; then
            printf '%s\n' "$result"
            break
          fi
        done
      )
    fi
  '';

  # Store config hash after successful activation for update-system to check
  system.activationScripts.storeConfigHash = let
    flakeDir = config.users.users.dreamingcodes.home + "/.nixos";
    hashFlakeState = import ../../lib/hash-flake-state.nix {inherit pkgs;};
  in ''
    FLAKE_DIR="${flakeDir}"
    CACHE_FILE="/var/lib/nixos-config-hash"
    if [[ -d "$FLAKE_DIR/.git" ]]; then
      HASH="$(${hashFlakeState}/bin/hash-flake-state "$FLAKE_DIR")"
      echo "$HASH" > "$CACHE_FILE"
    fi
  '';

  # Improved nix rebuild UX & cleanup timer
  programs.nh = {
    flake = config.users.users.dreamingcodes.home + "/.nixos/";
    clean = {
      enable = true;
      extraArgs = "--keep-since 3d --keep 2";
      dates = "daily";
    };
    enable = true;
  };
}
