{ config, pkgs, lib, ... }: {
  home-manager.users.dreamingcodes = {
    home.stateVersion = "24.11";
    programs.home-manager.enable = true;

    home.packages = with pkgs; [
      kdePackages.kate
      zed-editor
      brave
      telegram-desktop
      bitwarden
      vesktop
      prismlauncher
      btop
      alacritty
      bun
      nodejs
      bintools
      rustup
      kdePackages.kleopatra
      gnupg
      pinentry-qt
      fzf
      spotify
      tor-browser
      jetbrains-toolbox
    ];
    services = {
      easyeffects.enable = true;
      kdeconnect = {
        enable = true;
        indicator = true;
        package = pkgs.kdePackages.kdeconnect-kde;
      };
      gpg-agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-qt;
      };
    };
    programs = {
      zellij = {
        enable = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
      };
      micro = lib.mkForce { enable = false; };
      git = {
        enable = true;
        userName = "DreamingCodes";
        userEmail = "me@dreaming.codes";
        signing = {
          key = "1FE3A3F18110DDDD";
          signByDefault = true;
        };
        extraConfig = lib.mkDefault {
          core = { editor = "zed"; };
          init = { defaultBranch = "master"; };
          pull = { rebase = true; };
        };
      };
      gitui.enable = true;
      git-credential-oauth.enable = true;
      fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting # Disable greeting
          any-nix-shell fish | source
        '';
        shellAliases = {
          htop = "btop";
          shutdown = "systemctl poweroff";
        };
      };
      bash = { enable = true; };
      eza = {
        enable = true;
        extraOptions = [ "-al" "--icons" ];
      };
      bat = { enable = true; };
      direnv = { enable = true; };
      zoxide = {
        enable = true;
        options = [ "--cmd cd" ];
      };
    };
  };
}
