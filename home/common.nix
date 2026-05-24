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
  ];

  home.shell.enableShellIntegration = true;
  programs.home-manager.enable = true;

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

  # Comma integration with nix-index
  programs.nix-index-database.comma.enable = true;

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

  # Config file links shared by all users
  home.file."./.config/zellij" = {
    source = ../config/zellij;
    recursive = true;
  };

  home.file."./.config/helix" = {
    source = ../config/helix;
    recursive = true;
  };

  home.file."./.config/rio/config.toml" = {
    source = ../config/rio/config.toml;
    force = true;
  };

  xdg.desktopEntries.rio = {
    name = "Rio";
    genericName = "Terminal";
    exec = "rio";
    terminal = false;
    categories = ["System" "TerminalEmulator"];
  };

  home.file.".config/clangd/config.yaml".source = clangdConfig;

  home.file."./.cargo/config.toml".source = ../config/cargo/config.toml;

  home.file.".config/opencode/opencode.json".source = ../config/opencode/opencode.json;
  home.file.".config/opencode/opencode-notifier.json".source =
    ../config/opencode/opencode-notifier.json;
  home.file.".config/opencode/AGENTS.md".source = ../config/opencode/AGENTS.md;
  home.file.".config/opencode/agent/git-detective.md".source =
    ../config/opencode/agent/git-detective.md;

  programs = {
    # Shell and CLI tools
    helix.enable = true;

    fzf = {
      enable = true;
      enableFishIntegration = true;
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

        # Remap fzf keybindings to avoid zellij conflicts
        bind --erase \ct  # Remove Ctrl+T
        bind \et fzf-file-widget  # Alt+T for file search
        # Use bat as cat replacement in interactive shell
        function cat --wraps bat --description 'Use bat instead of cat'
          ${pkgs.bat}/bin/bat $argv
        end
        abbr -a dockertui oxker
      '';
      shellAliases = {
        htop = "btop";
        shutdown = "systemctl poweroff";
      };
      functions = {
        binds = ''
          echo "╔═══════════════════════════════════════════════════════════════╗"
          echo "║                      KEYBINDINGS                              ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  FISH SHELL                                                   ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Alt+T          File search (fzf)                             ║"
          echo "║  Ctrl+R         Command history (fzf)                         ║"
          echo "║  Alt+C          cd into directory (fzf)                       ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  HYPRLAND                                                     ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Super+Space    Open terminal (rio)                           ║"
          echo "║  Super+W        Open browser (brave)                          ║"
           echo "║  Super+X        Open DMS Spotlight                            ║"
          echo "║  Super+Q        Kill active window                            ║"
          echo "║  Super+F        Fullscreen                                    ║"
          echo "║  Super+O        Toggle floating                               ║"
          echo "║  Super+C        Clipboard (DMS)                               ║"
          echo "║  Super+L        Lock screen                                   ║"
          echo "║  Super+M        Toggle mixer                                  ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  APPS                                                         ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Super+T        Telegram                                      ║"
          echo "║  Super+D        Discord                                       ║"
          echo "║  Super+S        Signal                                        ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  SCREENSHOTS                                                  ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Print          Screenshot active window                      ║"
          echo "║  Shift+Print    Screenshot region                             ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  WINDOW MANAGEMENT                                            ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Super+Arrow    Move focus                                    ║"
          echo "║  Super+Shift+Arrow  Move window                               ║"
          echo "║  Super+Mouse    Move/resize window (left/right click)         ║"
          echo "║  Super+Scroll   Zoom cursor                                   ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  WORKSPACES                                                   ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Super+1-0      Switch to workspace 1-10                      ║"
          echo "║  Super+Shift+1-0  Move window to workspace 1-10               ║"
          echo "║  Super+F1-F12   Switch to workspace F1-F12                    ║"
          echo "║  Super+Shift+F1-F12  Move window to F1-F12                    ║"
          echo "║  Super+Alt+1-0  Switch to ALT workspace 1-10                  ║"
          echo "║  Super+Shift+Alt+1-0  Move to ALT workspace                   ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  WALLPAPER                                                    ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
           echo "║  Super+.        Next wallpaper                                ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  MEDIA                                                        ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  XF86AudioPlay  Play/Pause                                    ║"
          echo "║  XF86AudioPrev  Previous track                                ║"
          echo "║  XF86AudioNext  Next track                                    ║"
          echo "║  XF86AudioMicMute  Toggle microphone                          ║"
          echo "╚═══════════════════════════════════════════════════════════════╝"
        '';
      };
    };

    starship = {
      enable = true;
      settings = {
        aws.symbol = "  ";
        buf.symbol = " ";
        bun.symbol = " ";
        c.symbol = " ";
        cmake.symbol = "△ ";
        cmd_duration = {
          disabled = false;
          format = "took [$duration]($style)";
          min_time = 1;
        };
        conda.symbol = " ";
        crystal.symbol = " ";
        dart.symbol = " ";
        deno.symbol = " ";
        dotnet = {
          format = "via [$symbol($version )($tfm )]($style)";
          symbol = "󰪮 ";
        };
        directory = {
          read_only = " 󰌾";
          style = "purple";
          truncate_to_repo = true;
          truncation_length = 0;
          truncation_symbol = "repo: ";
        };
        docker_context.symbol = " ";
        elixir.symbol = " ";
        elm.symbol = " ";
        fennel.symbol = " ";
        fossil_branch.symbol = " ";
        git_branch.symbol = " ";
        gcloud.symbol = " ";
        golang.symbol = " ";
        guix_shell.symbol = " ";
        haskell.symbol = " ";
        haxe.symbol = " ";
        hg_branch.symbol = " ";
        hostname = {
          disabled = false;
          format = "[$hostname]($style) in ";
          ssh_only = false;
          ssh_symbol = " ";
          style = "bold dimmed red";
        };
        java.symbol = " ";
        julia.symbol = " ";
        kotlin.symbol = " ";
        kubernetes.symbol = "󱃾 ";
        lua.symbol = " ";
        maven.symbol = " ";
        memory_usage.symbol = "󰍛 ";
        meson.symbol = "󰔷 ";
        nim.symbol = "󰆥 ";
        mojo.symbol = "🔥 ";
        nix_shell.symbol = " ";
        nodejs.symbol = " ";
        ocaml.symbol = " ";
        package.symbol = "󰏗 ";
        perl.symbol = " ";
        php.symbol = " ";
        pijul_channel.symbol = " ";
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
        sudo = {
          disabled = false;
          symbol = " ";
        };
        swift.symbol = " ";
        terraform.symbol = "󱁢 ";
        username = {
          format = " [$user]($style)@";
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

    bash.enable = true;

    eza = {
      enable = true;
      enableFishIntegration = true;
      extraOptions = [
        "-al"
        "--icons"
      ];
    };

    bat.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
      options = ["--cmd cd"];
    };
  };
}
