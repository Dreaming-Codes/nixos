{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  home-manager.users.dreamingcodes = {
    home.stateVersion = "24.11";
    programs.home-manager.enable = true;

    # Hint Electron apps to use Wayland:
    home.sessionVariables.NIXOS_OZONE_WL = "1";
    home.sessionVariables.ZELLIJ_AUTO_EXIT = "true";

    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = ["qemu:///system"];
        uris = ["qemu:///system"];
      };
    };

    home.sessionPath = [
      "/home/dreamingcodes/.local/share/JetBrains/Toolbox/scripts/"
      "/home/dreamingcodes/.cargo/bin"
    ];

    programs.helix = {
      enable = true;
      settings = {
        theme = "material_darker";
        editor = {
          line-number = "relative";
          indent-guides.render = true;
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
        };
      };
      languages = {
        language-server = {
          tailwindcss-ls = {
            command = "tailwindcss-language-server";
            args = ["--stdio"];
          };
        };
        language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${pkgs.alejandra}/bin/alejandra";
          }
          {
            name = "svelte";
            language-servers = ["svelteserver" "tailwindcss-ls"];
          }
        ];
      };
    };

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
      plugins = with pkgs.obs-studio-plugins; [obs-backgroundremoval];
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
        indicator =
          false; # at time of writing there's a bug that make this fail
        package = pkgs.kdePackages.kdeconnect-kde;
      };
      gpg-agent = {
        enable = true;
        pinentryPackage = pkgs.kwalletcli;
        extraConfig = "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
      };
    };

    home.file."./.config/zellij" = {
      source = ./zellij;
      recursive = true;
    };

    home.file."./.config/wezterm" = {
      source = ./wezterm;
      recursive = true;
    };

    home.file."./.config/yazelix" = {
      source = builtins.fetchGit {
        url = "https://github.com/Dreaming-Codes/yazelix";
        rev = "da9875c2b1bdf45c276cae6989c233526a47c166";
      };
    };

    programs = {
      zellij = {
        enable = true;
        enableFishIntegration = true;
      };
      wezterm = {
        enable = true;
      };
      lazygit = {enable = true;};
      gitui = {enable = true;};
      fzf = {enable = true;};
      micro = lib.mkForce {enable = false;};
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
          core = {editor = "zeditor";};
          init = {defaultBranch = "master";};
          pull = {rebase = true;};
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
      yazi = {
        enable = true;
        enableNushellIntegration = true;
      };
      starship = {
        enable = true;
        enableNushellIntegration = true;
      };
      nushell = {
        enable = true;
        extraConfig = ''
          $env.config.show_banner = false
          source ${pkgs.nix-your-shell.generate-config "nu"}
        '';
      };
      carapace = {
        enable = true;
        enableNushellIntegration = true;
        enableFishIntegration = true;
      };
      bash = {enable = true;};
      eza = {
        enable = true;
        extraOptions = ["-al" "--icons"];
      };
      bat = {enable = true;};
      direnv = {
        enable = true;
        enableNushellIntegration = true;
        nix-direnv.enable = true;
      };
      zoxide = {
        enable = true;
        options = ["--cmd cd"];
      };
    };
  };
}
