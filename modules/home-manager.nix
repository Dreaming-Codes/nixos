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

    imports = [
      inputs.anyrun.homeManagerModules.default
    ];

    # Hint Electron apps to use Wayland:
    home.sessionVariables = {
      EDITOR = "hx";
      VISUAL = "hx";
      NIXOS_OZONE_WL = "1";
      ZELLIJ_AUTO_EXIT = "true";
    };
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

    programs.obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [obs-backgroundremoval];
    };

    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false;
      settings = {
        "$mod" = "SUPER";
        exec-once = [
          "ashell"
          "${pkgs.kwallet-pam}/libexec/pam_kwallet_init"
        ];
        monitor = [
          "HDMI-A-1, highres, 0x0, 1"
          "DP-1, 3440x1440@144, 1920x0, 1"
          "DP-2, highres, 5360x0, 1"
        ];
        workspace = [
          "1, persistent:true, monitor:DP-1"
          "2, persistent:true, monitor:DP-1"
          "3, persistent:true, monitor:DP-1"
          "4, persistent:true, monitor:DP-2"
          "5, persistent:true, monitor:DP-2"
          "6, persistent:true, monitor:DP-2"
          "7, persistent:true, monitor:HDMI-A-1"
          "8, persistent:true, monitor:HDMI-A-1"
          "9, persistent:true, monitor:HDMI-A-1"
        ];
        input = {
          kb_layout = "us";
          kb_variant = "intl";
        };
        windowrulev2 = [
          "opacity 0.0 override, class:^(xwaylandvideobridge)$"
          "noanim, class:^(xwaylandvideobridge)$"
          "noinitialfocus, class:^(xwaylandvideobridge)$"
          "maxsize 1 1, class:^(xwaylandvideobridge)$"
          "noblur, class:^(xwaylandvideobridge)$"
          "nofocus, class:^(xwaylandvideobridge)$"
        ];
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        bind =
          [
            "$mod, W, exec, brave"
            "$mod, SPACE, exec, wezterm"
            ", Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m active"
            "SHIFT, Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m region"
            "$mod, X, exec, anyrun"
            "$mod, Q, killactive"
          ]
          ++ (
            # workspaces
            builtins.concatLists (builtins.genList (
                i: let
                  ws = i + 1;
                in [
                  "$mod, code:1${toString i}, workspace, ${toString ws}"
                  "$mod SHIFT, code:1${toString 1}, movetoworkspace, ${toString ws}"
                ]
              )
              9)
          );
      };
    };

    home.packages = with pkgs; [
      inputs.Neve.packages.${pkgs.system}.default
      inputs.ashell.defaultPackage.${pkgs.system}
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

    home.file."./.config/helix" = {
      source = ./helix;
      recursive = true;
    };

    home.file."./.config/ashell.yml".source = ./ashell.yml;

    programs = {
      anyrun = {
        enable = true;
        extraConfigFiles = {
          "uwsm_app.ron".text = ''
            Config(
              desktop_actions: false,
              max_entries: 5,
            )
          '';

          "shell.ron".text = ''
            Config(
              prefix: ">"
            )
          '';

          "randr.ron".text = ''
            Config(
              prefi: ":dp",
              max_entries: 5,
            )
          '';
        };
        extraCss = ''
          * {
            all: unset;
            font-size: 1.2rem;
          }

          #window,
          #match,
          #entry,
          #plugin,
          #main {
            background: transparent;
          }

          #match.activatable {
            border-radius: 8px;
            margin: 4px 0;
            padding: 4px;
            /* transition: 100ms ease-out; */
          }
          #match.activatable:first-child {
            margin-top: 12px;
          }
          #match.activatable:last-child {
            margin-bottom: 0;
          }

          #match:hover {
            background: rgba(255, 255, 255, 0.05);
          }
          #match:selected {
            background: rgba(255, 255, 255, 0.1);
          }

          #entry {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            padding: 4px 8px;
          }

          box#main {
            background: rgba(0, 0, 0, 0.5);
            box-shadow:
              inset 0 0 0 1px rgba(255, 255, 255, 0.1),
              0 30px 30px 15px rgba(0, 0, 0, 0.5);
            border-radius: 20px;
            padding: 12px;
          }
        '';
        config = {
          width.fraction = 0.25;
          y.fraction = 0.3;
          hidePluginInfo = true;
          closeOnClick = true;
          plugins = with inputs.anyrun.packages.${pkgs.system}; [
            inputs.anyrunfufexan.packages.${pkgs.system}.uwsm_app
            randr
            rink
            shell
            symbols
          ];
        };
      };
      zellij = {
        enable = true;
        enableFishIntegration = true;
      };
      wezterm = {
        enable = true;
      };
      helix = {
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
