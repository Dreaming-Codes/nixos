{
  pkgs,
  lib,
  config,
  ...
}: let
  # Get GCC include paths for clangd
  gcc = pkgs.gcc;
  gccVersion = gcc.cc.version;
  gccPath = "${gcc.cc}/include/c++/${gccVersion}";
  gccTargetPath = "${gcc.cc}/include/c++/${gccVersion}/x86_64-unknown-linux-gnu";
  gccBackwardPath = "${gcc.cc}/include/c++/${gccVersion}/backward";
  gccLibPath = "${gcc.cc}/lib/gcc/x86_64-unknown-linux-gnu/${gccVersion}/include";
  gccIncludePath = "${gcc.cc}/include";
  gccLibFixedPath = "${gcc.cc}/lib/gcc/x86_64-unknown-linux-gnu/${gccVersion}/include-fixed";
  glibcIncludePath = "${pkgs.glibc.dev}/include";

  clangdConfig = pkgs.writeText "clangd-config.yaml" ''
    CompileFlags:
      Add:
        - "-isystem${gccPath}"
        - "-isystem${gccTargetPath}"
        - "-isystem${gccBackwardPath}"
        - "-isystem${gccLibPath}"
        - "-isystem${gccIncludePath}"
        - "-isystem${gccLibFixedPath}"
        - "-isystem${glibcIncludePath}"
  '';

  rbwPinentryKwallet = pkgs.writeShellApplication {
    name = "rbw-pinentry-kwallet";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.kdePackages.kwallet
      pkgs.perl
      pkgs.pinentry-qt
      pkgs.qt6.qttools
    ];
    text = ''
      set -euo pipefail

      rbw_profile="rbw"
      if [ -n "''${RBW_PROFILE:-}" ]; then
        rbw_profile="rbw-''${RBW_PROFILE}"
      fi

      wallet="kdewallet"
      folder="rbw"
      entry="$rbw_profile master password"

      wallet_handle() {
        qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open "$wallet" 0 rbw-pinentry-kwallet 2>/dev/null
      }

      assuan_escape() {
        perl -pe 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g'
      }

      assuan_unescape() {
        perl -pe 's/%([0-9A-Fa-f]{2})/chr(hex($1))/eg'
      }

      read_secret() {
        handle="$(wallet_handle)" || return 0
        qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword "$handle" "$folder" "$entry" rbw-pinentry-kwallet 2>/dev/null || true
      }

      ensure_folder() {
        handle="$(wallet_handle)" || return 1
        qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder "$handle" "$folder" rbw-pinentry-kwallet >/dev/null 2>&1 || true
      }

      write_secret() {
        handle="$(wallet_handle)" || return 1
        qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.writePassword "$handle" "$folder" "$entry" "$1" rbw-pinentry-kwallet >/dev/null
      }

      prompt_pinentry() {
        printf 'SETTITLE %s\nSETPROMPT %s\nSETDESC %s\nGETPIN\n' "$title" "$prompt" "$desc" \
          | pinentry-qt "$@"
      }

      prompt_and_store_secret() {
        pinentry_output="$(prompt_pinentry "$@")"
        password="$(printf '%s\n' "$pinentry_output" | sed -n 's/^D //p' | head -n1 | assuan_unescape)"

        if [ -z "$password" ]; then
          return 1
        fi

        ensure_folder || true
        write_secret "$password"
        printf '%s' "$password"
      }

      case "''${1:-}" in
        -h|--help|help)
          printf 'Use as rbw pinentry, backed by KWallet.\n'
          exit 0
          ;;
        -c|--clear|clear)
          ensure_folder || true
          write_secret "" || true
          exit 0
          ;;
      esac

      title="rbw"
      prompt=""
      desc=""
      had_error=0

      echo "OK"
      while IFS=' ' read -r command args; do
        case "$command" in
          SETTITLE)
            title="$args"
            echo "OK"
            ;;
          SETPROMPT)
            prompt="$args"
            echo "OK"
            ;;
          SETDESC)
            desc="$args"
            echo "OK"
            ;;
          SETERROR)
            had_error=1
            echo "OK"
            ;;
          GETPIN)
            if [ "$prompt" = "Master Password" ]; then
              secret=""
              if [ "$had_error" = 0 ]; then
                secret="$(read_secret)"
              fi
              if [ -z "$secret" ]; then
                if ! secret="$(prompt_and_store_secret "$@")"; then
                  echo "ERR 83886179 canceled"
                  continue
                fi
              fi
              had_error=0
              printf 'D %s\n' "$(printf '%s' "$secret" | assuan_escape)"
              echo "OK"
            else
              prompt_pinentry "$@" | sed -n '/^D /p; /^ERR /p; /^OK/p' | tail -n2
            fi
            ;;
          BYE)
            echo "OK"
            exit 0
            ;;
          *)
            echo "OK"
            ;;
        esac
      done
    '';
  };

  mimes = import ../lib/mimes.nix;
in {
  imports = [
    ../modules/nix-file-overlay/hm-module.nix
    ./cli.nix
  ];

  programs.nix-file-overlay = {
    enable = true;
    repoPath = "/home/dreamingcodes/.nixos";
    systemRepoPath = "/home/dreamingcodes/.nixos";
  };

  home.activation.mimeApps = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${mimes.bindMimes "brave-origin-nightly.desktop" [
      "application/pdf"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "text/html"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
      "x-scheme-handler/webcal"
      "x-scheme-handler/mailto"
    ]}

    # Set dolphin as default file manager
    ${mimes.bindMimes "org.kde.dolphin.desktop" ["inode/directory"]}
  '';

  # Configure KDE defaults used by KDE apps outside Plasma.
  home.activation.configureKdeTerminal = lib.hm.dag.entryAfter ["writeBoundary"] ''
    /run/current-system/sw/bin/kwriteconfig6 --file kdeglobals --group General --key TerminalApplication "rio"
    /run/current-system/sw/bin/kwriteconfig6 --file kdeglobals --group General --key TerminalService "rio.desktop"
  '';

  # rbw SSH agent
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/rbw/ssh-agent-socket";
    OPENCODE_EXPERIMENTAL = "1";
    OPENCODE_EXPERIMENTAL_PLAN_MODE = "1";
    TERMINAL = "rio";
    GTK_THEME = "adw-gtk3-dark";
    QT_QPA_PLATFORMTHEME = "kde";
    QT_QPA_PLATFORMTHEME_QT6 = "kde";
  };

  home.activation.themeSessionEnvironment = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
      ${pkgs.systemd}/bin/systemctl --user set-environment \
        GTK_THEME=adw-gtk3-dark \
        QT_QPA_PLATFORMTHEME=kde \
        QT_QPA_PLATFORMTHEME_QT6=kde
      GTK_THEME=adw-gtk3-dark \
      QT_QPA_PLATFORMTHEME=kde \
      QT_QPA_PLATFORMTHEME_QT6=kde \
        ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
        GTK_THEME QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME_QT6 >/dev/null 2>&1 || true
    fi
  '';

  # Auto-unlock rbw on graphical session start (uses pinentry-qt)
  systemd.user.services.rbw-unlock = {
    Unit = {
      Description = "Unlock rbw on session start";
      Wants = ["kwallet-pam.service"];
      After = [
        "graphical-session.target"
        "kwallet-pam.service"
      ];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.rbw}/bin/rbw unlock";
      RemainAfterExit = true;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  home.activation.rbwSessionTimeout = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -x ${pkgs.rbw}/bin/rbw ]; then
      ${pkgs.rbw}/bin/rbw config set lock_timeout 31536000
      ${pkgs.rbw}/bin/rbw config set pinentry ${config.home.homeDirectory}/.local/state/nix/profiles/home-manager/home-path/bin/rbw-pinentry-kwallet
    fi
  '';

  # Common session paths
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ];

  home.packages = [
    rbwPinentryKwallet
  ];

  xdg.desktopEntries.rio = {
    name = "Rio";
    genericName = "Terminal";
    exec = "rio";
    terminal = false;
    categories = ["System" "TerminalEmulator"];
  };

  home.file.".config/clangd/config.yaml".source = clangdConfig;
}
