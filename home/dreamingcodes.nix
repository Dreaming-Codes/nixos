{
  pkgs,
  lib,
  config,
  inputs,
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
  codexStandalone = pkgs.writeShellScriptBin "codex" ''
    exec /home/dreamingcodes/.codex/packages/standalone/current/bin/codex "$@"
  '';
  syncDmsKdeColors = pkgs.writeShellScriptBin "sync-dms-kde-colors" ''
    set -euo pipefail

    home_dir="''${HOME:-/home/dreamingcodes}"
    kde_color_scheme="$home_dir/.local/share/color-schemes/DankMatugen.colors"
    kdeglobals="$home_dir/.config/kdeglobals"
    qt5_color_scheme="$home_dir/.config/qt5ct/colors/matugen.conf"
    qt6_color_scheme="$home_dir/.config/qt6ct/colors/matugen.conf"

    [ -f "$kde_color_scheme" ] || exit 0
    mkdir -p "$(${pkgs.coreutils}/bin/dirname "$kdeglobals")"
    touch "$kdeglobals"

    for qt_color_scheme in "$qt5_color_scheme" "$qt6_color_scheme"; do
      if [ -f "$qt_color_scheme" ]; then
        ${pkgs.gnused}/bin/sed -i -E 's/#([0-9a-fA-F]{6})([,[:space:]]|$)/#ff\1\2/g' "$qt_color_scheme"
      fi
    done

    tmp_kdeglobals="$(${pkgs.coreutils}/bin/mktemp)"
    ${pkgs.gawk}/bin/awk '
      function synced_group(section) {
        return section ~ /^(ColorEffects:|Colors:|KDE$|WM$)/
      }
      FNR == NR {
        if ($0 ~ /^\[/) {
          section = substr($0, 2, length($0) - 2)
          keep = synced_group(section)
        }
        if (keep) {
          synced = synced $0 "\n"
        }
        next
      }
      $0 ~ /^\[/ {
        section = substr($0, 2, length($0) - 2)
        skip = synced_group(section)
      }
      !skip { print }
      END {
        printf "%s", synced
      }
    ' "$kde_color_scheme" "$kdeglobals" > "$tmp_kdeglobals"
    ${pkgs.coreutils}/bin/mv "$tmp_kdeglobals" "$kdeglobals"

    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --notify --file "$kdeglobals" --group General --key ColorScheme "DankMatugen"
    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --notify --file "$kdeglobals" --group General --key Name "Dank Shell (matugen)"
    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --notify --file "$kdeglobals" --group General --key ColorSchemeHash "$(${pkgs.coreutils}/bin/sha256sum "$kde_color_scheme" | ${pkgs.gawk}/bin/awk '{print $1}')"
    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$kdeglobals" --group KDE --key LookAndFeelPackage --delete
    PATH="/run/current-system/sw/bin:$PATH" dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 >/dev/null 2>&1 || true
  '';
  mimes = import ../lib/mimes.nix;
  dmsSettingsDefaults = builtins.fromJSON (builtins.readFile ../config/dms/defaults/settings.json);
  dmsSessionDefaults = builtins.fromJSON (builtins.readFile ../config/dms/defaults/session.json);
  dmsPluginDefaults = builtins.fromJSON (builtins.readFile ../config/dms/defaults/plugin_settings.json);
in {
  imports = [
    inputs.codex-desktop-linux.homeManagerModules.default
  ];

  xdg.configFile."hypr/hyprland.conf".force = true;
  xdg.configFile."btop/btop.conf".force = true;

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
    if [ ! -x /home/dreamingcodes/.codex/packages/standalone/current/bin/codex ]; then
      ${pkgs.curl}/bin/curl -fsSL https://chatgpt.com/codex/install.sh | sh
    fi
    mkdir -p /home/dreamingcodes/.local/bin
    ln -sfn /home/dreamingcodes/.codex/packages/standalone/current/bin/codex /home/dreamingcodes/.local/bin/codex
  '';

  programs.codexDesktopLinux = {
    enable = true;
    computerUseUi.enable = true;
    remoteMobileControl.enable = true;
    remoteControl = {
      enable = true;
      package = codexStandalone;
    };
  };

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
    "/home/dreamingcodes/.local/bin"
    "/home/dreamingcodes/.local/share/JetBrains/Toolbox/scripts/"
    "/home/dreamingcodes/.cargo/bin"
    "/home/dreamingcodes/.bun/bin"
  ];

  home.sessionVariables = {
    CODEX_UPDATE_MANAGER_PATH = "${pkgs.coreutils}/bin/false";
  };

  systemd.user.sessionVariables = {
    CODEX_UPDATE_MANAGER_PATH = "${pkgs.coreutils}/bin/false";
  };

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
    merge_defaults "$DMS_CONFIG/plugin_settings.json" '${builtins.toJSON dmsPluginDefaults}'
    merge_defaults "$DMS_STATE/session.json" '${builtins.toJSON dmsSessionDefaults}'
  '';

  home.activation.darkGtkNativeTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set_ini_key() {
      file="$1"
      key="$2"
      value="$3"
      mkdir -p "$(${pkgs.coreutils}/bin/dirname "$file")"
      if [ ! -f "$file" ]; then
        printf '[Settings]\n%s=%s\n' "$key" "$value" > "$file"
      elif ${pkgs.gnugrep}/bin/grep -q "^$key=" "$file"; then
        ${pkgs.gnused}/bin/sed -i "s|^$key=.*|$key=$value|" "$file"
      elif ${pkgs.gnugrep}/bin/grep -q '^\[Settings\]' "$file"; then
        ${pkgs.gnused}/bin/sed -i "/^\[Settings\]/a $key=$value" "$file"
      else
        printf '\n[Settings]\n%s=%s\n' "$key" "$value" >> "$file"
      fi
    }

    set_xsettings_key() {
      file="$1"
      key="$2"
      value="$3"
      mkdir -p "$(${pkgs.coreutils}/bin/dirname "$file")"
      if [ ! -f "$file" ]; then
        printf '%s "%s"\n' "$key" "$value" > "$file"
      elif ${pkgs.gnugrep}/bin/grep -q "^$key " "$file"; then
        ${pkgs.gnused}/bin/sed -i "s|^$key .*|$key \"$value\"|" "$file"
      else
        printf '%s "%s"\n' "$key" "$value" >> "$file"
      fi
    }

    remove_ini_key() {
      file="$1"
      key="$2"
      if [ -f "$file" ]; then
        ${pkgs.gnused}/bin/sed -i "/^$key=/d" "$file"
      fi
    }

    set_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-theme-name adw-gtk3-dark
    set_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-application-prefer-dark-theme true
    set_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-theme-name adw-gtk3-dark
    set_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-application-prefer-dark-theme true
    remove_ini_key "$HOME/.config/gtk-3.0/settings.ini" gtk-modules
    remove_ini_key "$HOME/.config/gtk-4.0/settings.ini" gtk-modules

    if [ -f "$HOME/.gtkrc-2.0" ]; then
      if ${pkgs.gnugrep}/bin/grep -q '^gtk-theme-name=' "$HOME/.gtkrc-2.0"; then
        ${pkgs.gnused}/bin/sed -i 's|^gtk-theme-name=.*|gtk-theme-name="adw-gtk3-dark"|' "$HOME/.gtkrc-2.0"
      else
        printf 'gtk-theme-name="adw-gtk3-dark"\n' >> "$HOME/.gtkrc-2.0"
      fi
    fi

    set_xsettings_key "$HOME/.config/xsettingsd/xsettingsd.conf" Net/ThemeName adw-gtk3-dark

    ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
    ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-dark'"
    ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/icon-theme "'breeze-dark'"
  '';

  home.activation.dmsQtColors = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set_ini_key() {
      file="$1"
      section="$2"
      key="$3"
      value="$4"
      mkdir -p "$(${pkgs.coreutils}/bin/dirname "$file")"
      if [ ! -f "$file" ]; then
        printf '[%s]\n%s=%s\n' "$section" "$key" "$value" > "$file"
      elif ${pkgs.gnugrep}/bin/grep -q "^$key=" "$file"; then
        ${pkgs.gnused}/bin/sed -i "s|^$key=.*|$key=$value|" "$file"
      elif ${pkgs.gnugrep}/bin/grep -q "^\[$section\]" "$file"; then
        ${pkgs.gnused}/bin/sed -i "/^\[$section\]/a $key=$value" "$file"
      else
        printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
      fi
    }

    qt5_color_scheme="$HOME/.config/qt5ct/colors/matugen.conf"
    qt6_color_scheme="$HOME/.config/qt6ct/colors/matugen.conf"
    set_ini_key "$HOME/.config/qt5ct/qt5ct.conf" Appearance custom_palette true
    set_ini_key "$HOME/.config/qt5ct/qt5ct.conf" Appearance color_scheme_path "$qt5_color_scheme"
    set_ini_key "$HOME/.config/qt6ct/qt6ct.conf" Appearance custom_palette true
    set_ini_key "$HOME/.config/qt6ct/qt6ct.conf" Appearance color_scheme_path "$qt6_color_scheme"

    ${syncDmsKdeColors}/bin/sync-dms-kde-colors
  '';

  home.file.".face.icon".source = ../config/hypr/dreamingcodes.jpeg;

  home.activation.dmsProfileImage = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PROFILE_IMAGE="$HOME/.config/hypr/dreamingcodes.jpeg"
    if [ -e "$PROFILE_IMAGE" ] && command -v busctl >/dev/null 2>&1; then
      busctl --system call \
        org.freedesktop.Accounts \
        /org/freedesktop/Accounts/User$(id -u) \
        org.freedesktop.Accounts.User \
        SetIconFile s "$PROFILE_IMAGE" >/dev/null 2>&1 || true
    fi
  '';

  home.activation.hyprlandDmsIncludes = lib.hm.dag.entryAfter ["writeBoundary"] ''
    HYPR_DIR="$HOME/.config/hypr"
    HYPR_CONF="$HYPR_DIR/hyprland.conf"
    DMS_DIR="$HYPR_DIR/dms"
    mkdir -p "$DMS_DIR"
    touch \
      "$DMS_DIR/binds.conf" \
      "$DMS_DIR/colors.conf" \
      "$DMS_DIR/cursor.conf" \
      "$DMS_DIR/layout.conf" \
      "$DMS_DIR/outputs.conf" \
      "$DMS_DIR/windowrules.conf"

    if [ -L "$HYPR_CONF" ]; then
      GENERATED="$(${pkgs.coreutils}/bin/readlink -f "$HYPR_CONF")"
      TMP="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.coreutils}/bin/cp "$GENERATED" "$TMP"
      ${pkgs.coreutils}/bin/mv "$TMP" "$HYPR_CONF"
      ${pkgs.coreutils}/bin/chmod u+w "$HYPR_CONF"
    elif [ -e "$HYPR_CONF" ]; then
      ${pkgs.coreutils}/bin/chmod u+w "$HYPR_CONF"
    fi

    ensure_source() {
      line="$1"
      target="$2"
      if ! ${pkgs.gnugrep}/bin/grep -Eq "^[[:space:]]*source[[:space:]]*=[[:space:]]*\\./dms/$target[[:space:]]*$" "$HYPR_CONF"; then
        printf '\n%s\n' "$line" >> "$HYPR_CONF"
      fi
    }

    ensure_source "source = ./dms/colors.conf" "colors.conf"
    ensure_source "source = ./dms/cursor.conf" "cursor.conf"
    ensure_source "source = ./dms/layout.conf" "layout.conf"
    ensure_source "source = ./dms/outputs.conf" "outputs.conf"
    ensure_source "source = ./dms/windowrules.conf" "windowrules.conf"
    ensure_source "source = ./dms/binds.conf" "binds.conf"
  '';

  home.activation.niriDmsIncludes = lib.hm.dag.entryAfter ["writeBoundary"] ''
    NIRI_DIR="$HOME/.config/niri"
    NIRI_CONF="$NIRI_DIR/config.kdl"
    DMS_DIR="$NIRI_DIR/dms"
    mkdir -p "$DMS_DIR"

    make_writable_file() {
      path="$1"
      if [ -L "$path" ]; then
        GENERATED="$(${pkgs.coreutils}/bin/readlink -f "$path")"
        TMP="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.coreutils}/bin/cp "$GENERATED" "$TMP"
        ${pkgs.coreutils}/bin/mv "$TMP" "$path"
        ${pkgs.coreutils}/bin/chmod u+w "$path"
      elif [ -e "$path" ]; then
        ${pkgs.coreutils}/bin/chmod u+w "$path"
      else
        ${pkgs.coreutils}/bin/touch "$path"
      fi
    }

    make_writable_file "$NIRI_CONF"

    seed_file() {
      path="$1"
      source="$2"
      if [ ! -e "$path" ]; then
        ${pkgs.coreutils}/bin/cp "$source" "$path"
        ${pkgs.coreutils}/bin/chmod u+w "$path"
      fi
    }

    seed_file "$DMS_DIR/alttab.kdl" "${../config/niri/dms/alttab.kdl}"
    seed_file "$DMS_DIR/binds.kdl" "${../config/niri/dms/binds.kdl}"
    seed_file "$DMS_DIR/colors.kdl" "${../config/niri/dms/colors.kdl}"
    seed_file "$DMS_DIR/cursor.kdl" "${../config/niri/dms/cursor.kdl}"
    seed_file "$DMS_DIR/layout.kdl" "${../config/niri/dms/layout.kdl}"
    seed_file "$DMS_DIR/outputs.kdl" "${../config/niri/dms/outputs.kdl}"
    seed_file "$DMS_DIR/windowrules.kdl" "${../config/niri/dms/windowrules.kdl}"

    for target in alttab.kdl binds.kdl colors.kdl cursor.kdl layout.kdl outputs.kdl windowrules.kdl; do
      make_writable_file "$DMS_DIR/$target"
      if ! ${pkgs.gnugrep}/bin/grep -Eq "^[[:space:]]*include[[:space:]]+\"dms/$target\"[[:space:]]*$" "$NIRI_CONF"; then
        printf '\ninclude "dms/%s"\n' "$target" >> "$NIRI_CONF"
      fi
    done
  '';

  # Virt-manager dconf settings (qemu:///system access)
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = ["qemu:///system"];
      uris = ["qemu:///system"];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "adw-gtk3-dark";
      icon-theme = "breeze-dark";
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
      bind =
        [
          "$mod, mouse_down, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 1.2; if (val < 1) val=1; print val}')"
          "$mod, mouse_up, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | awk '/^float.*/ {val = $2 * 0.8; if (val < 1) val=1; print val}')"
          "$mod, W, exec, brave-origin-nightly"
          "$mod, SPACE, exec, rio"
          ", Print, exec, dms screenshot full"
          "SHIFT, Print, exec, dms screenshot"
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
    extraConfig = ''
      source = ./dms/colors.conf
      source = ./dms/cursor.conf
      source = ./dms/layout.conf
      source = ./dms/outputs.conf
      source = ./dms/windowrules.conf
      source = ./dms/binds.conf
    '';
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

  # KWallet daemon for auto-unlock in Wayland sessions
  systemd.user.services.kwallet-pam = {
    Unit = {
      Description = "KWallet PAM Auto-unlock";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "-${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init";
      Type = "oneshot";
    };
  };

  systemd.user.services.dms-kde-matugen-colors = {
    Unit = {
      Description = "Sync DMS matugen colors into KDE globals";
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 1";
      ExecStart = "${syncDmsKdeColors}/bin/sync-dms-kde-colors";
    };
  };

  systemd.user.paths.dms-kde-matugen-colors = {
    Unit = {
      Description = "Watch DMS matugen KDE color scheme";
    };
    Path = {
      PathChanged = "%h/.local/share/color-schemes/DankMatugen.colors";
      PathModified = "%h/.local/share/color-schemes/DankMatugen.colors";
      TriggerLimitIntervalSec = 0;
      Unit = "dms-kde-matugen-colors.service";
    };
    Install = {
      WantedBy = ["default.target"];
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
    codexStandalone
    syncDmsKdeColors
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

  home.file."./.config/niri/config.kdl" = {
    source = ../config/niri/config.kdl;
    force = true;
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

    btop = {
      enable = true;
      settings = {
        graph_symbol = "block";
        graph_symbol_cpu = "block";
        graph_symbol_gpu = "block";
        graph_symbol_mem = "block";
        graph_symbol_net = "block";
        graph_symbol_proc = "block";
      };
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
