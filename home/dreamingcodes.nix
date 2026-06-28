{
  pkgs,
  lib,
  config,
  inputs,
  osConfig,
  ...
}: let
  vibeMerge = pkgs.writeShellScriptBin "vibe-merge" (builtins.readFile ../scripts/vibeMerge.sh);
  vibeCommit = pkgs.writeShellScriptBin "vibe-commit" (builtins.readFile ../scripts/vibeCommit.sh);
  codexStandalone = pkgs.writeShellScriptBin "codex" ''
    exec /home/dreamingcodes/.codex/packages/standalone/current/bin/codex "$@"
  '';
  codexRemoteControlPath = lib.makeSearchPath "bin" [
    config.home.profileDirectory
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.openssh
  ];
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
  dmsPluginDefaults = builtins.fromJSON (
    builtins.readFile ../config/dms/defaults/plugin_settings.json
  );
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
    if [ ! -x /home/dreamingcodes/.codex/packages/standalone/current/bin/codex ]; then
      ${pkgs.curl}/bin/curl -fsSL https://chatgpt.com/codex/install.sh | sh
    fi
    mkdir -p /home/dreamingcodes/.local/bin
    ln -sfn /home/dreamingcodes/.codex/packages/standalone/current/bin/codex /home/dreamingcodes/.local/bin/codex
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
    "/home/dreamingcodes/.local/bin"
    "/home/dreamingcodes/.local/share/JetBrains/Toolbox/scripts/"
    "/home/dreamingcodes/.cargo/bin"
    "/home/dreamingcodes/.bun/bin"
  ];

  systemd.user.services.codex-remote-control = {
    Unit = {
      Description = "Codex remote-control app-server";
      Documentation = "file:%h/.codex/packages/standalone/current/codex";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      Environment = [
        "CODEX_HOME=/home/dreamingcodes/.codex"
        "PATH=${codexRemoteControlPath}"
        "LOG_FORMAT=json"
        "RUST_LOG=info,codex_app_server_transport::transport::remote_control=debug"
      ];
      ExecStartPre = "-${pkgs.coreutils}/bin/rm -f %h/.codex/app-server-control/app-server-control.sock";
      ExecStart = "${codexStandalone}/bin/codex app-server --remote-control --listen unix://";
      KillMode = "control-group";
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 10;
    };
    Install = {
      WantedBy = ["default.target"];
    };
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

  home.file.".face.icon".source = ../config/dreamingcodes.jpeg;

  home.activation.dmsProfileImage = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PROFILE_IMAGE="$HOME/.face.icon"
    if [ -e "$PROFILE_IMAGE" ] && command -v busctl >/dev/null 2>&1; then
      busctl --system call \
        org.freedesktop.Accounts \
        /org/freedesktop/Accounts/User$(id -u) \
        org.freedesktop.Accounts.User \
        SetIconFile s "$PROFILE_IMAGE" >/dev/null 2>&1 || true
    fi
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
    seed_file "$DMS_DIR/host-local.kdl" "${../config/niri/dms/host-local.kdl}"
    seed_file "$DMS_DIR/layout.kdl" "${../config/niri/dms/layout.kdl}"
    seed_file "$DMS_DIR/outputs.kdl" "${../config/niri/dms/outputs.kdl}"
    seed_file "$DMS_DIR/windowrules.kdl" "${../config/niri/dms/windowrules.kdl}"

    for target in alttab.kdl binds.kdl colors.kdl cursor.kdl host-local.kdl layout.kdl outputs.kdl windowrules.kdl; do
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
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular";
      Restart = "on-failure";
      Type = "simple";
    };
  };

  home.packages = [
    vibeMerge
    vibeCommit
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
  home.file.".config/niri/config.kdl" = {
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
    mangohud = {
      # MangoHud is a gaming FPS overlay; only meaningful on the x86 desktop/laptop.
      enable = pkgs.stdenv.hostPlatform.isx86_64;
      enableSessionWide = pkgs.stdenv.hostPlatform.isx86_64;
      settings = {
        full = true;
        no_display = true;
        cpu_load_change = true;
      };
    };

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

    # Base git config is shared in home/cli.nix; this adds the Linux-only
    # libsecret credential helper.
    git.settings.credential = {
      helper = [
        "libsecret"
        "${pkgs.git-credential-oauth}/bin/git-credential-oauth"
      ];
    };
  };
}
