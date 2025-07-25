{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: {
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
      # Allow using flakes & automatically optimize the nix store
      auto-optimise-store = true;

      # Use available binary caches, this is not Gentoo
      # this also allows us to use remote builders to reduce build times and batter usage
      builders-use-substitutes = true;

      # We are using flakes, so enable the experimental features
      experimental-features = ["nix-command" "flakes" "dynamic-derivations" "repl-flake"];

      # Users allowed to use Nix
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];

      # Max number of parallel jobs
      max-jobs = "auto";

      # https://github.com/NixOS/nix/issues/8890#issuecomment-1703988345
      nix-path = nixPath;

      # Relax sandbox to allow DMI access for QEMU spoofing
      sandbox = "relaxed";
    };

    # Make legacy nix commands consistent as well
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    # Use the Lix package manager
    package = pkgs.lix;

    # Automtaically pin registries based on inputs
    registry = lib.mapAttrs (_: v: {flake = v;}) inputs;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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

  # Improved nix rebuild UX & cleanup timer
  programs.nh = {
    flake = "/home/dreamingcodes/.nixos/";
    clean = {
      enable = true;
      extraArgs = "--keep-since 3d --keep 2";
      dates = "daily";
    };
    enable = true;
  };
}
