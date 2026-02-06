{
  pkgs,
  lib,
  inputs,
  ...
}: let
  toggleMic = pkgs.writeShellScriptBin "toggleMic" (builtins.readFile ../scripts/mictoggle.sh);
  toggleMixer = pkgs.writeShellScriptBin "toggleMixer" (builtins.readFile ../scripts/mixer.sh);
  vibeMerge = pkgs.writeShellScriptBin "vibe-merge" (builtins.readFile ../scripts/vibeMerge.sh);
  vibeCommit = pkgs.writeShellScriptBin "vibe-commit" (builtins.readFile ../scripts/vibeCommit.sh);
  razerPower = pkgs.writeShellScriptBin "razer-power" (builtins.readFile ../scripts/razerpower.sh);
  mimes = import ../lib/mimes.nix;
in {
  imports = [
    inputs.vicinae.homeManagerModules.default
  ];

  # Set default applications (DreamingCodes specific)
  home.activation.dreamingCodesMimeApps = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${mimes.bindMimes "Helix.desktop" mimes.textMimes}
  '';

  programs.fish = {
    completions = {
      vibe-merge = ''
        set -l PATH_TO_WORKTREES ".rsworktree"
        complete -c vibe-merge -f -a "(test -d $PATH_TO_WORKTREES; and command ls -1 $PATH_TO_WORKTREES)"
      '';
    };
  };

  # DreamingCodes-specific session paths
  home.sessionPath = [
    "/home/dreamingcodes/.local/share/JetBrains/Toolbox/scripts/"
    "/home/dreamingcodes/.cargo/bin"
    "/home/dreamingcodes/.bun/bin"
  ];

  services.vicinae = {
    enable = true;
    package = pkgs.vicinae;
    systemd = {
      enable = true;
      autoStart = true;
      environment = {
        USE_LAYER_SHELL = 1;
      };
    };
    extensions = with inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      bluetooth
      it-tools
      nix
      player-pilot
      port-killer
      power-profile
      process-manager
      wifi-commander
    ];
  };

  # Vicinae base config (read-only, imported by user settings.json)
  home.file.".config/vicinae/base-config.json".text = builtins.toJSON {
    close_on_focus_loss = true;
    pop_to_root_on_close = true;
    favorites = [];
    font = {
      normal = {
        family = "FiraCode Nerd Font";
      };
    };
    providers = {
      "@Gelei/bluetooth-0" = {
        preferences.connectionToggleable = true;
      };
      "@gebeto/store.raycast.translate" = {
        preferences.autoInput = true;
        entrypoints = {
          instant-translate-copy.enabled = false;
          instant-translate-paste.enabled = false;
          instant-translate-view.enabled = false;
          quick-translate.enabled = true;
          translate.enabled = false;
          translate-form.enabled = false;
        };
      };
      "@knoopx/nix-0" = {
        entrypoints.flake-packages.enabled = true;
      };
      "@marcjulian/store.raycast.obsidian" = {
        preferences = {
          removeLatex = false;
          removeLinks = false;
          removeYAML = false;
          vaultPath = "/home/dreamingcodes/Documents/Obsidian Vault";
        };
        entrypoints = {
          appendTaskCommand.enabled = false;
          dailyNoteAppendCommand.enabled = false;
          dailyNoteCommand.enabled = false;
          openVaultCommand.enabled = false;
          openWorkspaceCommand.enabled = false;
          randomNoteCommand.enabled = false;
          searchMedia.enabled = false;
        };
      };
      "@mattisssa/store.raycast.spotify-player" = {
        entrypoints = {
          findLyrics.enabled = false;
          generatePlaylist.enabled = false;
          next.enabled = false;
          previous.enabled = false;
          search.preferences.musicOnly = true;
          togglePlayPause.enabled = false;
          volume.enabled = true;
        };
      };
      "@ratoru/store.raycast.google-maps-search" = {
        preferences = {
          preferredMode = "driving";
          preferredOrigin = "home";
          useSelected = true;
        };
        entrypoints = {
          find.enabled = false;
          quickSearchMaps.enabled = false;
          travelHome.enabled = false;
          travelTo.alias = "driveto";
        };
      };
      clipboard = {
        preferences.encryption = true;
        entrypoints.history.preferences.defaultAction = "copy";
      };
      core = {
        entrypoints = {
          about.enabled = false;
          documentation.enabled = false;
          keybind-settings.enabled = false;
          list-extensions.enabled = false;
          open-config-file.enabled = false;
          open-default-config.enabled = false;
          report-bug.enabled = false;
          sponsor.enabled = false;
        };
      };
      files = {
        enabled = false;
        preferences.autoIndexing = true;
      };
      power = {
        entrypoints = {
          hibernate.enabled = false;
          sleep.enabled = false;
        };
      };
      theme.enabled = false;
    };
  };

  # Create settings.json with imports if it doesn't exist or doesn't have imports
  home.activation.vicinaSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    SETTINGS_FILE="$HOME/.config/vicinae/settings.json"
    if [ ! -f "$SETTINGS_FILE" ] || ! grep -q '"imports"' "$SETTINGS_FILE" 2>/dev/null; then
      mkdir -p "$(dirname "$SETTINGS_FILE")"
      echo '{"imports": ["base-config.json"]}' > "$SETTINGS_FILE"
    fi
  '';

  # Virt-manager dconf settings (qemu:///system access)
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = ["qemu:///system"];
      uris = ["qemu:///system"];
    };
  };

  programs.obs-studio.enable = true;

  # Hyprland window manager configuration
  wayland.windowManager.hyprland = {
    enable = true;
    systemd = {
      enable = true;
      variables = ["--all"];
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
        tablet = {
          output = "current";
        };
      };
      general = {
        gaps_out = 0;
        gaps_in = 0;
      };
      gestures = {
        workspace_swipe_forever = true;
      };
      gesture = [
        "3, horizontal, workspace"
      ];
      windowrule = [
        "opacity 0.0 override, no_anim on, no_initial_focus on, max_size 1 1, no_blur on, no_focus on, match:class ^(xwaylandvideobridge)$"
        "stay_focused on, match:class expo-orbit"
      ];
      binds = {
        scroll_event_delay = 0;
      };
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
      workspace = [
        "special:obsidian, on-created-empty:obsidian"
      ];
      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };
      bind =
        [
          "$mod, mouse_down, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 1.2; if (val < 1) val=1; print val}')"
          "$mod, mouse_up, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 0.8; if (val < 1) val=1; print val}')"
          "$mod, W, exec, helium"
          "$mod, SPACE, exec, wezterm"
          ", Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m active"
          "SHIFT, Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m region"
          "$mod, X, exec, vicinae open"
          "$mod, Q, killactive"
          "$mod, T, exec, Telegram"
          "$mod, D, exec, discord"
          "$mod, S, exec, signal-desktop"
          "$mod, O, togglefloating"
          "$mod, C, exec, vicinae deeplink vicinae://extensions/vicinae/clipboard/history"
          "$mod, L, exec, hyprlock"
          "$mod, F, fullscreen"
          "$mod, M, exec, toggleMixer"
          "$mod, comma, exec, wpaperctl previous"
          "$mod, period, exec, wpaperctl next"
          ", code:121, exec, toggleMic"
          # Move focus with arrow keys or hjkl
          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"
          "$mod SHIFT, left, movewindow, l"
          "$mod SHIFT, right, movewindow, r"
          "$mod SHIFT, up, movewindow, u"
          "$mod SHIFT, down, movewindow, d"
          "$mod, N, togglespecialworkspace, obsidian"
          # Audio keys
          ", XF86AudioMicMute, exec, toggleMic"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioPrev, exec, playerctl previous"
          ", XF86AudioNext, exec,playerctl next"
        ]
        ++ (
          # workspaces
          let
            # Generate 1–9 and 0 (mapped to 10)
            numWorkspaces =
              builtins.genList (
                i: let
                  ws =
                    if i == 9
                    then 10
                    else i + 1;
                  key =
                    if i == 9
                    then "0"
                    else toString (i + 1);
                in [
                  "$mod, ${key}, workspace, ${toString ws}"
                  "$mod SHIFT, ${key}, movetoworkspace, ${toString ws}"
                ]
              )
              10;

            # Generate F1–F12
            fWorkspaces =
              builtins.genList (
                i: let
                  ws = "F${toString (i + 1)}";
                  key = "F${toString (i + 1)}";
                in [
                  "$mod, ${key}, workspace, name:${ws}"
                  "$mod SHIFT, ${key}, movetoworkspace, name:${ws}"
                ]
              )
              12;

            # Generate ALT1–ALT10 (with ALT0 = ALT10)
            altWorkspaces =
              builtins.genList (
                i: let
                  ws =
                    if i == 9
                    then "ALT10"
                    else "ALT${toString (i + 1)}";
                  key =
                    if i == 9
                    then "0"
                    else toString (i + 1);
                in [
                  "$mod ALT, ${key}, workspace, name:${ws}"
                  "$mod SHIFT ALT, ${key}, movetoworkspace, name:${ws}"
                ]
              )
              10;
          in
            builtins.concatLists (numWorkspaces ++ fWorkspaces ++ altWorkspaces)
        );
    };
  };

  # Hyprland-related services
  services.wpaperd.enable = true;
  services.wpaperd.settings = {
    any = {
      duration = "30m";
      mode = "center";
      sorting = "random";
      path = "~/Pictures/wallpaper";
    };
  };
  systemd.user.services.wpaperd = {
    Unit = {
      PartOf = lib.mkForce ["hyprland-session.target"];
      After = lib.mkForce ["hyprland-session.target"];
    };
    Install.WantedBy = lib.mkForce ["hyprland-session.target"];
  };

  services.swaync.enable = true;
  systemd.user.services.swaync = {
    Unit = {
      PartOf = lib.mkForce ["hyprland-session.target"];
      After = lib.mkForce ["hyprland-session.target"];
    };
    Install.WantedBy = lib.mkForce ["hyprland-session.target"];
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
  systemd.user.services.hypridle = {
    Unit = {
      PartOf = lib.mkForce ["hyprland-session.target"];
      After = lib.mkForce ["hyprland-session.target"];
    };
    Install.WantedBy = lib.mkForce ["hyprland-session.target"];
  };

  systemd.user.services.ashell = {
    Unit = {
      Description = "ashell";
      PartOf = ["hyprland-session.target"];
      After = ["hyprland-session.target"];
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
    Service = {
      ExecStart = "/run/current-system/sw/bin/ashell";
      Restart = "always";
      Type = "simple";
    };
  };

  # KWallet daemon for auto-unlock with Hyprland
  systemd.user.services.kwallet-pam = {
    Unit = {
      Description = "KWallet PAM Auto-unlock";
      PartOf = ["hyprland-session.target"];
      After = ["hyprland-session.target"];
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init";
      Type = "oneshot";
    };
  };

  # Clipboard persistence for Wayland - keeps clipboard data after apps close
  systemd.user.services.wl-clip-persist = {
    Unit = {
      Description = "Persistent clipboard for Wayland";
      PartOf = ["hyprland-session.target"];
      After = ["hyprland-session.target"];
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular";
      Restart = "on-failure";
      Type = "simple";
    };
  };

  # DreamingCodes-only packages (toggleMic/toggleMixer scripts)
  home.packages = [
    toggleMic
    toggleMixer
    vibeMerge
    vibeCommit
    razerPower
  ];

  # Services
  services = {
    easyeffects.enable = true;
    kdeconnect = {
      enable = true;
      indicator = false; # at time of writing there's a bug that make this fail
      package = pkgs.kdePackages.kdeconnect-kde;
    };
    gpg-agent = {
      enable = true;
      pinentry.package = pkgs.kwalletcli;
      extraConfig = "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
    };
  };

  # DreamingCodes-specific config files
  home.file."./.config/ashell" = {
    source = ../config/ashell;
    recursive = true;
  };

  home.file."./.config/hypr" = {
    source = ../config/hypr;
    recursive = true;
  };

  home.file."./Pictures/wallpaper" = {
    source = ../config/wallpaper;
    recursive = true;
  };

  home.file."./.config/spotify-player" = {
    source = ../config/spotify-player;
    recursive = true;
  };

  home.file."./.local/lib/wireshark/extcap" = {
    source = ../config/extcap;
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

    pay-respects.enable = true;

    zellij = {
      enable = true;
      enableFishIntegration = true;
      exitShellOnExit = true;
    };

    lazygit.enable = true;
    gitui.enable = true;

    yazi = {
      enable = true;
      enableFishIntegration = true;
    };

    git = {
      enable = true;
      package = pkgs.gitFull;
      signing = {
        key = "1FE3A3F18110DDDD";
        signByDefault = true;
      };
      settings = {
        user = {
          name = "DreamingCodes";
          email = "me@dreaming.codes";
        };
        core = {
          editor = "hx";
        };
        init = {
          defaultBranch = "master";
        };
        pull = {
          rebase = true;
        };
        push = {
          autoSetupRemote = true;
        };
        diff = {
          external = "difft";
        };
        credential = {
          helper = [
            "libsecret"
            "${pkgs.git-credential-oauth}/bin/git-credential-oauth"
          ];
        };
      };
    };
  };
}
