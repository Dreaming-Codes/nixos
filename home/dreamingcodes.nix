{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}: let
  toggleMic = pkgs.writeShellScriptBin "toggleMic" (builtins.readFile ../scripts/mictoggle.sh);
  toggleMixer = pkgs.writeShellScriptBin "toggleMixer" (builtins.readFile ../scripts/mixer.sh);
  vibeMerge = pkgs.writeShellScriptBin "vibe-merge" (builtins.readFile ../scripts/vibeMerge.sh);
  vibeCommit = pkgs.writeShellScriptBin "vibe-commit" (builtins.readFile ../scripts/vibeCommit.sh);
  opencode = pkgs.writeShellScriptBin "opencode" ''
    exec ${pkgs.bun}/bin/bunx opencode-ai@latest "$@"
  '';
  mimes = import ../lib/mimes.nix;
  dmsSettingsDefaults = {
    currentThemeName = "blue";
    displayNameMode = "system";
    displayProfileAutoSelect = false;
    launcherPluginOrder = [
      "applications"
      "dankBitwarden"
      "dankSpotify"
      "dankTranslate"
      "nixPackageRunner"
      "nixMonitor"
      "openTrackerBar"
      "RazerEnergy"
    ];
    launcherPluginVisibility = {
      dankBitwarden.allowWithoutTrigger = true;
      dankSpotify.allowWithoutTrigger = true;
      dankTranslate.allowWithoutTrigger = true;
      nixPackageRunner.allowWithoutTrigger = true;
      nixMonitor.allowWithoutTrigger = true;
      openTrackerBar.allowWithoutTrigger = true;
      RazerEnergy.allowWithoutTrigger = true;
    };
    matugenTemplateHyprland = true;
    showClipboard = true;
    showNotificationButton = true;
    wallpaperFillMode = "Fill";
  };
  dmsSessionDefaults = {
    launchPrefix = "";
    perMonitorWallpaper = false;
    showThirdPartyPlugins = true;
    wallpaperCyclingEnabled = true;
    wallpaperCyclingInterval = 600;
    wallpaperCyclingMode = "interval";
    wallpaperPath = "/home/dreamingcodes/Pictures/wallpaper/42.jpg";
    wallpaperTransition = "fade";
  };
in {
  # Set default applications (DreamingCodes specific)
  home.activation.dreamingCodesMimeApps = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${mimes.bindMimes "Helix.desktop" mimes.textMimes}
  '';

  # Install Rust toolchains and required components for Helix/rust-analyzer
  home.activation.rustupToolchains = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/home/dreamingcodes/.cargo/bin:$PATH"
    if command -v rustup &> /dev/null; then
      run rustup toolchain install stable --profile default
      run rustup toolchain install nightly --profile default

      # Keep analyzer and sources available on nightly (default toolchain)
      run rustup component add rust-src --toolchain nightly
      run rustup component add rust-analyzer --toolchain nightly
      run rustup component add clippy --toolchain nightly
      run rustup component add rustfmt --toolchain nightly

      # Also keep stable ready for projects that pin stable
      run rustup component add rust-src --toolchain stable
      run rustup component add rust-analyzer --toolchain stable
      run rustup component add clippy --toolchain stable
      run rustup component add rustfmt --toolchain stable

      run rustup default nightly
    fi
  '';

  home.activation.codexStandalone = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -x /home/dreamingcodes/.local/bin/codex ]; then
      ${pkgs.curl}/bin/curl -fsSL https://chatgpt.com/codex/install.sh | sh
    fi
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

  home.activation.dmsDefaults = lib.hm.dag.entryAfter ["writeBoundary"] ''
    DMS_CONFIG="$HOME/.config/DankMaterialShell"
    DMS_STATE="$HOME/.local/state/DankMaterialShell"
    mkdir -p "$DMS_CONFIG" "$DMS_STATE"

    merge_defaults() {
      target="$1"
      defaults="$2"
      if [ ! -s "$target" ]; then
        printf '%s\n' "$defaults" > "$target"
        return
      fi
      tmp="$(mktemp)"
      if ${pkgs.jq}/bin/jq --argjson defaults "$defaults" '$defaults * .' "$target" > "$tmp"; then
        mv "$tmp" "$target"
      else
        rm -f "$tmp"
      fi
    }

    merge_defaults "$DMS_CONFIG/settings.json" '${builtins.toJSON dmsSettingsDefaults}'
    merge_defaults "$DMS_STATE/session.json" '${builtins.toJSON dmsSessionDefaults}'
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
    # Home-manager flipped the default from "hyprlang" (writes hyprland.conf)
    # to "lua" (writes hyprland.lua) for stateVersion >= 26.05. Hyprland still
    # reads hyprland.conf by default, so keep the hyprlang format until we
    # explicitly migrate to the lua config.
    configType = "hyprlang";
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
      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };
      source = [
        "./dms/outputs.conf"
      ];
      bind =
        [
          "$mod, mouse_down, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 1.2; if (val < 1) val=1; print val}')"
          "$mod, mouse_up, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 0.8; if (val < 1) val=1; print val}')"
          "$mod, W, exec, brave-origin-nightly"
          "$mod, SPACE, exec, wezterm"
          ", Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m active"
          "SHIFT, Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m region"
          "$mod, Q, killactive"
          "$mod, T, exec, Telegram"
          "$mod, D, exec, discord"
          "$mod, S, exec, signal-desktop"
          "$mod, O, togglefloating"
          "$mod, C, exec, dms ipc call clipboard toggle"
          "$mod, L, exec, dms ipc call lock lock"
          "$mod, F, fullscreen"
          "$mod, M, exec, toggleMixer"
          "$mod, X, exec, dms ipc call spotlight toggle"
          "$mod, period, exec, dms ipc call wallpaper next"

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

  services.hypridle.enable = true;
  services.hypridle.settings = {
    general = {
      lock_cmd = "dms ipc call lock lock";
      before_sleep_cmd = "dms ipc call lock lock";
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
        on-timeout = "dms ipc call lock lock";
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

  systemd.user.services.codex-remote-control = {
    Unit = {
      Description = "Codex remote-control app-server";
      Documentation = "file:%h/.codex/packages/standalone/current/codex";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Install = {
      WantedBy = ["default.target"];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %h/.codex/app-server-control/app-server-control.sock";
      ExecStart = "%h/.local/bin/codex app-server --remote-control --listen unix://";
      Environment = [
        "LOG_FORMAT=json"
        "RUST_LOG=info,codex_app_server_transport::transport::remote_control=debug"
      ];
      KillMode = "control-group";
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 10;
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
    opencode
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
      pinentry.package = pkgs.pinentry-qt;
      extraConfig = "pinentry-program ${pkgs.pinentry-qt}/bin/pinentry-qt";
    };
  };

  # DreamingCodes-specific config files
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
