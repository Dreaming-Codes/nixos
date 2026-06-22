{
  pkgs,
  lib,
  config,
  inputs,
  nix-index-database,
  ...
}:
let
  # Machine-local private Nix settings (e.g. an internal binary cache) live
  # OUTSIDE this public repo so their URLs/keys are never committed. The build
  # must be run with `--impure` for this absolute path to be read.
  localNixSettingsPath = "/Users/dreamingcodes/.config/nixos-local/local-nix-settings.nix";
  hasLocalNixSettings = builtins.pathExists localNixSettingsPath;
  localNixSettings = if hasLocalNixSettings then import localNixSettingsPath else { };
in
{
  imports = [
    ./paneru.nix
    ./skhd.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = 6;
  system.primaryUser = "dreamingcodes";

  # ── Nix: let Determinate Nix own /etc/nix/nix.conf ────────
  # determinate.darwinModules.default is imported via mkDarwin commonModule.
  # nix-darwin must NOT manage nix itself, otherwise it fights Determinate.
  nix.enable = false;

  determinateNix.customSettings = {
    # Generic substituter resilience / performance tuning (not sensitive).
    fallback = true;
    narinfo-cache-meta-ttl = 86400;
    narinfo-cache-negative-ttl = 900;
    connect-timeout = 3;
    download-attempts = 5;
    download-buffer-size = 524288000;
    auto-optimise-store = true;
    min-free = 1073741824;
  }
  # Machine-local private settings, loaded from outside the repo.
  // localNixSettings;

  # Require the machine-local settings on this machine. If the file is missing,
  # fail loudly rather than silently building without it.
  # NOTE: reading the local file requires `--impure`; without it the path is
  # not visible and this assertion will trip, which is the intended signal.
  assertions = [
    {
      assertion = hasLocalNixSettings;
      message = ''
        Expected local Nix settings at ${localNixSettingsPath} but it was not found.

        This file holds machine-local private Nix settings (kept outside the
        public flake). Restore it, then rebuild with `--impure`, e.g.:

          nh darwin switch -- --impure
      '';
    }
  ];

  # Parity with the Linux config: disable Determinate telemetry.
  environment.variables.DETSYS_IDS_TELEMETRY = "disabled";

  environment.variables.NH_FLAKE = "/Users/dreamingcodes/.nixos";

  programs.fish.enable = true;
  environment.shells = [ pkgs.fish ];

  security.pam.services.sudo_local.touchIdAuth = true;

  # User
  # Hand the existing account to nix-darwin so it sets the login shell (fish)
  # via dscl. This is safe for this primary account despite the usual warning:
  #   * `system.primaryUser = "dreamingcodes"` makes nix-darwin REFUSE TO BUILD
  #     if this user ever lands in `deletedUsers` (i.e. removed from users.users
  #     while still in knownUsers).
  #   * the deletion activation only runs `dscl -delete` when `uid > 501`; this
  #     account is uid 501, so the delete path is structurally skipped anyway.
  # uid/gid must match the existing macOS account (501 / staff=20) or nix-darwin
  # skips it with an "unexpected uid" warning.
  users.knownUsers = [ "dreamingcodes" ];
  users.users.dreamingcodes = {
    uid = 501;
    gid = 20;
    home = "/Users/dreamingcodes";
    shell = pkgs.fish;
  };

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.symbols-only
    dejavu_fonts
  ];

  environment.systemPackages = with pkgs; [
    git
    nh
  ];

  # Used only for apps that would otherwise compile from source under
  # nix (e.g. bitwarden-desktop is not in the binary cache on aarch64-darwin).
  # cleanup = "none": never uninstall casks/brews that aren't listed here, so
  # manually-installed Homebrew apps are left untouched.
  homebrew = {
    enable = true;
    enableFishIntegration = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
      # Activation runs `brew bundle` under sudo, which does NOT inherit
      # environment.variables. Set HOMEBREW_NO_REQUIRE_TAP_TRUST here so the
      # non-interactive bundle doesn't block on the third-party tap trust prompt.
      extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
    };
    taps = [
      "supercmdlabs/supercmd"
    ];
    casks = [
      "bitwarden"
    ];
  };

  # Home-Manager wiring (mirrors modules/users/dreamingcodes.nix)
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs; };
  home-manager.backupFileExtension = "hm-backup";

  home-manager.users.dreamingcodes = {
    imports = [
      nix-index-database.homeModules.nix-index
      ../../home/dreamingcodes-darwin.nix
    ];
  };
}
