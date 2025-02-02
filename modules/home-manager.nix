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
        settings = {
          aws.symbol = "  ";
          buf.symbol = " ";
          c.symbol = " ";
          cmd_duration = {
            disabled = false;
            format = "took [$duration]($style)";
            min_time = 1;
          };
          conda.symbol = " ";
          crystal.symbol = " ";
          dart.symbol = " ";
          directory = {
            read_only = " 󰌾";
            style = "purple";
            truncate_to_repo = true;
            truncation_length = 0;
            truncation_symbol = "repo: ";
          };
          docker_context.symbol = " ";
          elixir.symbol = " ";
          elm.symbol = " ";
          fennel.symbol = " ";
          fossil_branch.symbol = " ";
          git_branch.symbol = " ";
          golang.symbol = " ";
          guix_shell.symbol = " ";
          haskell.symbol = " ";
          haxe.symbol = " ";
          hg_branch.symbol = " ";
          hostname = {
            disabled = false;
            format = "[$hostname]($style) in ";
            ssh_only = false;
            ssh_symbol = " ";
            style = "bold dimmed red";
          };
          java.symbol = " ";
          julia.symbol = " ";
          kotlin.symbol = " ";
          lua.symbol = " ";
          memory_usage.symbol = "󰍛 ";
          meson.symbol = "󰔷 ";
          nim.symbol = "󰆥 ";
          nix_shell.symbol = " ";
          nodejs.symbol = " ";
          ocaml.symbol = " ";
          package.symbol = "󰏗 ";
          perl.symbol = " ";
          php.symbol = " ";
          pijul_channel.symbol = " ";
          python.symbol = " ";
          rlang.symbol = "󰟔 ";
          ruby.symbol = " ";
          rust.symbol = " ";
          scala.symbol = " ";
          scan_timeout = 10;
          status = {
            disabled = false;
            map_symbol = true;
          };
          sudo.disabled = false;
          swift.symbol = " ";
          username = {
            format = " [$user]($style)@";
            show_always = true;
            style_root = "bold red";
            style_user = "bold red";
          };
          zig.symbol = " ";
        };
      };
      nushell = {
        enable = true;
        extraConfig = ''
          $env.config.show_banner = false
          source ${pkgs.nix-your-shell.generate-config "nu"}

          def start_zellij [] {
            if 'ZELLIJ' not-in ($env | columns) {
              if 'ZELLIJ_AUTO_ATTACH' in ($env | columns) and $env.ZELLIJ_AUTO_ATTACH == 'true' {
                zellij attach -c
              } else {
                zellij
              }

              if 'ZELLIJ_AUTO_EXIT' in ($env | columns) and $env.ZELLIJ_AUTO_EXIT == 'true' {
                exit
              }
            }
          }

          start_zellij
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
