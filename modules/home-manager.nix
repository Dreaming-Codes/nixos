{ config, pkgs, lib, inputs, ... }: {
  home-manager.users.dreamingcodes = {
    home.stateVersion = "24.11";
    programs.home-manager.enable = true;

    # Hint Electron apps to use Wayland:
    home.sessionVariables.NIXOS_OZONE_WL = "1";
    home.sessionVariables.ZELLIJ_AUTO_EXIT = "true";

    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };

    home.sessionPath = [
      "/home/dreamingcodes/.local/share/JetBrains/Toolbox/scripts/"
      "/home/dreamingcodes/.cargo/bin"
    ];

    programs.alacritty = {
      enable = true;
      settings = {
        font = {
          normal = {
            family = "FiraCode Nerd Font Mono";
            style = "Regular";
          };
          bold = {
            family = "FiraCode Nerd Font Mono";
            style = "Bold";
          };
        };
      };
    };

    programs.obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [ obs-backgroundremoval ];
    };

    home.packages = with pkgs; [
      inputs.Neve.packages.${pkgs.system}.default
      kdePackages.kate
      goldwarden
      brave
      telegram-desktop
      bitwarden-desktop
      equibop
      prismlauncher
      btop
      bun
      nodejs
      bintools
      rustup
      kdePackages.kleopatra
      gnupg
      kwalletcli
      spotify
      tor-browser
      jetbrains-toolbox
    ];
    services = {
      easyeffects.enable = true;
      kdeconnect = {
        enable = true;
        indicator = false; # at time of writing there's a bug that make this fail
        package = pkgs.kdePackages.kdeconnect-kde;
      };
      gpg-agent = {
        enable = true;
        pinentryPackage = pkgs.kwalletcli;
        extraConfig =
          "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
      };
    };

    home.file."./.config/zellij/config.kdl".source = ./zellij.kdl;

    programs = {
      zellij = {
        enable = true;
        enableFishIntegration = true;
      };
      lazygit = { enable = true; };
      gitui = { enable = true; };
      fzf = { enable = true; };
      micro = lib.mkForce { enable = false; };
      git = {
        enable = true;
        userName = "DreamingCodes";
        userEmail = "me@dreaming.codes";
        package = pkgs.gitFull;
        signing = {
          key = "1FE3A3F18110DDDD";
          signByDefault = true;
        };
        extraConfig = lib.mkForce {
          core = { editor = "zeditor"; };
          init = { defaultBranch = "master"; };
          pull = { rebase = true; };
          credential = {
            helper = [
              "libsecret"
              "${pkgs.git-credential-oauth}/bin/git-credential-oauth"
            ];
          };
        };
      };
      fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting # Disable greeting
          nix-your-shell fish | source
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
      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
      zoxide = {
        enable = true;
        options = [ "--cmd cd" ];
      };
    };
  };
}
