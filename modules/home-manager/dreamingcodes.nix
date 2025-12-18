{
  pkgs,
  lib,
  inputs,
  ...
}: let
  toggleMic = pkgs.writeShellScriptBin "toggleMic" (builtins.readFile ../mictoggle.sh);
  toggleMixer = pkgs.writeShellScriptBin "toggleMixer" (builtins.readFile ../mixer.sh);
in {
  imports = [
    inputs.gauntlet.homeManagerModules.default
  ];

  # DreamingCodes-specific session paths
  home.sessionPath = [
    "/home/dreamingcodes/.local/share/JetBrains/Toolbox/scripts/"
    "/home/dreamingcodes/.cargo/bin"
    "/home/dreamingcodes/.bun/bin"
  ];

  programs.gauntlet = {
    enable = true;
    service.enable = true;
    config = {};
  };

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
      windowrulev2 = [
        "opacity 0.0 override, class:^(xwaylandvideobridge)$"
        "noanim, class:^(xwaylandvideobridge)$"
        "noinitialfocus, class:^(xwaylandvideobridge)$"
        "maxsize 1 1, class:^(xwaylandvideobridge)$"
        "noblur, class:^(xwaylandvideobridge)$"
        "nofocus, class:^(xwaylandvideobridge)$"
        "stayfocused, class:expo-orbit"
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
      bind =
        [
          "$mod, mouse_down, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 1.2; if (val < 1) val=1; print val}')"
          "$mod, mouse_up, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 0.8; if (val < 1) val=1; print val}')"
          "$mod, W, exec, helium"
          "$mod, SPACE, exec, wezterm"
          ", Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m active"
          "SHIFT, Print, exec, ${pkgs.hyprshot}/bin/hyprshot -m region"
          "$mod, X, exec, gauntlet open"
          "$mod, Q, killactive"
          "$mod, T, exec, Telegram"
          "$mod, D, exec, discord"
          "$mod, S, exec, signal-desktop"
          "$mod, O, togglefloating"
          "$mod, C, exec, gauntlet run https://github.com/Mrid22/gauntlet-clipboard template-view :primary"
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

  # DreamingCodes-only packages (toggleMic/toggleMixer scripts)
  home.packages = [
    toggleMic
    toggleMixer
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
    source = ../ashell;
    recursive = true;
  };

  home.file."./.config/clipcat" = {
    source = ../clipcat;
    recursive = true;
  };

  home.file."./.config/hypr" = {
    source = ../hypr;
    recursive = true;
  };

  home.file."./Pictures/wallpaper" = {
    source = ../wallpaper;
    recursive = true;
  };

  home.file."./.config/spotify-player" = {
    source = ../spotify-player;
    recursive = true;
  };

  home.file."./.local/lib/wireshark/extcap" = {
    source = ../extcap;
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
