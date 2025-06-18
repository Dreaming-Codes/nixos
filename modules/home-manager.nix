{
  pkgs,
  lib,
  inputs,
  astal,
  ags,
  nix-index-database,
  ...
}: {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.dreamingcodes = {
    home.stateVersion = "24.11";
    home.shell.enableShellIntegration = true;
    programs.home-manager.enable = true;

    imports = [
      nix-index-database.hmModules.nix-index
    ];
    programs.nix-index-database.comma.enable = true;

    # Hint Electron apps to use Wayland:
    home.sessionVariables = {
      EDITOR = "hx";
      VISUAL = "hx";
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORMTHEME = "kde";
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
      "/home/dreamingcodes/.bun/bin"
      "/home/dreamingcodes/.local/bin"
    ];

    programs.obs-studio = {
      enable = true;
    };

    wayland.windowManager.hyprland = {
      enable = true;
      systemd = {
        enable = true;
        enableXdgAutostart = true;
      };
      # Those are both null since it's installed by the nixos module
      package = null;
      portalPackage = null;
      settings = {
        "$mod" = "SUPER";
        device = [
          {
            name = "cda3-touchpad";
            sensitivity = 0.25;
          }
        ];
        input = {
          kb_layout = "us";
          kb_variant = "intl";
          touchpad = {
            tap-and-drag = false;
          };
        };
        general = {
          gaps_out = 0;
          gaps_in = 0;
        };
        gestures = {
          workspace_swipe = true;
          workspace_swipe_min_fingers = true;
          workspace_swipe_forever = true;
        };
        windowrulev2 = [
          "opacity 0.0 override, class:^(xwaylandvideobridge)$"
          "noanim, class:^(xwaylandvideobridge)$"
          "noinitialfocus, class:^(xwaylandvideobridge)$"
          "maxsize 1 1, class:^(xwaylandvideobridge)$"
          "noblur, class:^(xwaylandvideobridge)$"
          "nofocus, class:^(xwaylandvideobridge)$"
          "stayfocused, class:expo-orbit"
        ];
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        bind =
          [
            "$mod, W, exec, google-chrome-stable"
            "$mod, SPACE, exec, wezterm"
            ", Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m active"
            "SHIFT, Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m region"
            "$mod, X, exec, anyrun"
            "$mod, Q, killactive"
            "$mod, T, exec, Telegram"
            "$mod, S, exec, signal-desktop"
            "$mod, O, togglefloating"
            "$mod, C, exec, clipcat-menu"
            "$mod, L, exec, hyprlock"
            "$mod, F, fullscreen"
            "$mod, M, exec, toggleMixer"
            "$mod, comma, exec, wpaperctl previous"
            "$mod, period, exec, wpaperctl next"
            ", code:121, exec, toggleMic"
            # Move focus with arrow keys or hjkl
            "$mod, left, movefocus, l"
            "$mod SHIFT, H, movefocus, l"
            "$mod, right, movefocus, r"
            "$mod SHIFT, L, movefocus, r"
            "$mod, up, movefocus, u"
            "$mod SHIFT, K, movefocus, u"
            "$mod, down, movefocus, d"
            "$mod SHIFT, J, movefocus, d"
            # Scroll workspaces with mouse
            "$mod, mouse_down, workspace, e+1"
            "$mod, mouse_up, workspace, e-1"
            # Audio keys
            # ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
            # ", XF86AudioLowerVolume, exec, swayosd-client --output-volume lower"
            # ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
            ", XF86AudioMicMute, exec, toggleMic"
            ", XF86AudioPlay, exec, playerctl play-pause"
            ", XF86AudioPrev, exec, playerctl previous"
            ", XF86AudioNext, exec,playerctl next"
            # ", XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
            # ", XF86MonBrightnessUp, exec, swayosd-client --brightness raise"
          ]
          ++ (
            # workspaces
            builtins.concatLists (builtins.genList (
                i: let
                  ws = i + 1;
                in [
                  "$mod, code:1${toString i}, workspace, ${toString ws}"
                  "$mod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
                ]
              )
              9)
          );
      };
    };

    services.wpaperd.enable = true;
    services.wpaperd.settings = {
      default = {
        duration = "30m";
        mode = "center";
        sorting = "random";
        path = "~/Pictures/wallpaper";
      };
    };

    services.hypridle.enable = true;
    services.hypridle.settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 150;
          on-timeout = "brightnessctl -s set 10";
          on-resume = "brightnessctl -r";
        }
        {
          timeout = 300;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
        }
        {
          timeout = 480;
          on-timeout = "systemctl suspend";
        }
      ];
    };

    systemd.user.services.clipcat = {
      Unit = {
        Description = "Clipcat Daemon";
        PartOf = ["hyprland-session.target"];
        After = ["hyprland-session.target"];
      };
      Install = {
        WantedBy = ["hyprland-session.target"];
      };
      Service = {
        ExecStartPre = "/run/current-system/sw/bin/rm -f %t/clipcat/grpc.sock";
        ExecStart = "/run/current-system/sw/bin/clipcatd --no-daemon --replace";
        Restart = "on-failure";
        Type = "simple";
      };
    };

    systemd.user.services.hyprpanel = {
      Unit = {
        Description = "Hyprpanel";
        PartOf = ["hyprland-session.target"];
        After = ["hyprland-session.target"];
      };
      Install = {
        WantedBy = ["hyprland-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.hyprpanel}/bin/hyprpanel";
        Restart = "always";
        Type = "simple";
      };
    };

    home.packages = with pkgs; let
      anyrun = inputs.anyrun.packages.${pkgs.system}.default;
      anyrunStdin = inputs.anyrun.packages.${pkgs.system}.stdin;
      dmenuWrapper = pkgs.writeShellScriptBin "dmenu" ''
        exec ${anyrun}/bin/anyrun --show-results-immediately true --plugins ${anyrunStdin}/lib/libstdin.so "$@"
      '';
      toggleMic = pkgs.writeShellScriptBin "toggleMic" ./mictoggle.sh;
      toggleMixer = pkgs.writeShellScriptBin "toggleMixer" ./mixer.sh;
    in [
      astal.packages.${system}.default
      ags.packages.${system}.default
      hyprpanel
      kdePackages.kate
      goldwarden
      telegram-desktop
      bitwarden-desktop
      prismlauncher
      btop
      bun
      nodejs
      bintools
      rustup
      kdePackages.kleopatra
      gnupg
      kwalletcli
      tor-browser
      jetbrains-toolbox
      dmenuWrapper
      toggleMic
      toggleMixer
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

    home.file."./.config/clipcat" = {
      source = ./clipcat;
      recursive = true;
    };

    home.file."./.config/hypr" = {
      source = ./hypr;
      recursive = true;
    };

    home.file."./Pictures/wallpaper" = {
      source = ./wallpaper;
      recursive = true;
    };

    home.file."./.config/spotify-player" = {
      source = ./spotify-player;
      recursive = true;
    };

    programs = {
      gpg = {
        enable = true;
        settings = {
          cert-digest-algo = "SHA512";
          charset = "utf-8";
          default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
          fixed-list-mode = true;
          keyid-format = "0xlong";
          list-options = "show-uid-validity";
          no-comments = true;
          no-emit-version = true;
          no-greeting = true;
          no-symkey-cache = true;
          personal-cipher-preferences = "AES256 AES192 AES";
          personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
          personal-digest-preferences = "SHA512 SHA384 SHA256";
          require-cross-certification = true;
          s2k-cipher-algo = "AES256";
          s2k-digest-algo = "SHA512";
          throw-keyids = true;
          verify-options = "show-uid-validity";
          with-fingerprint = true;
        };
      };
      pay-respects = {
        enable = true;
      };
      anyrun = {
        enable = true;
        extraConfigFiles = {
          "applications.ron".text = ''
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

          "stdin.ron".text = ''
            Config(
              allow_invalid: true,
              max_entries: 20
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
            applications
            randr
            shell
            symbols
          ];
        };
      };
      zellij = {
        enable = true;
        enableFishIntegration = true;
        exitShellOnExit = true;
      };
      wezterm = {
        enable = true;
      };
      helix = {
        enable = true;
        package = inputs.helix.packages.${pkgs.system}.default;
      };
      lazygit = {enable = true;};
      gitui = {enable = true;};
      fzf = {
        enable = true;
        enableFishIntegration = true;
      };
      git = {
        enable = true;
        userName = "DreamingCodes";
        userEmail = "me@dreaming.codes";
        package = pkgs.gitFull;
        signing = {
          key = "1FE3A3F18110DDDD";
          signByDefault = true;
        };
        extraConfig = {
          core = {editor = "hx";};
          init = {defaultBranch = "master";};
          pull = {rebase = true;};
          push = {
            autoSetupRemote = true;
          };
          credential = {
            helper = [
              "libsecret"
              "${pkgs.git-credential-oauth}/bin/git-credential-oauth"
            ];
          };
        };
      };
      nix-your-shell = {
        enable = true;
        enableFishIntegration = true;
      };
      fish = {
        enable = true;
        generateCompletions = false;
        interactiveShellInit = ''
          set fish_greeting # Disable greeting
        '';
        shellAliases = {
          htop = "btop";
          shutdown = "systemctl poweroff";
        };
      };
      yazi = {
        enable = true;
        enableFishIntegration = true;
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
      carapace = {
        enable = true;
        enableFishIntegration = true;
      };
      bash = {enable = true;};
      eza = {
        enable = true;
        enableFishIntegration = true;
        extraOptions = ["-al" "--icons"];
      };
      bat = {enable = true;};
      direnv = {
        enable = true;
        # enableFishIntegration = true;
        nix-direnv.enable = true;
      };
      zoxide = {
        enable = true;
        enableFishIntegration = true;
        options = ["--cmd cd"];
      };
    };
  };
}
