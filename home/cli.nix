{
  pkgs,
  lib,
  config,
  ...
}: {
  home.stateVersion = "26.05";

  home.shell.enableShellIntegration = true;
  programs.home-manager.enable = true;

  # Comma integration with nix-index (cross-platform)
  programs.nix-index-database.comma.enable = true;

  # Config file links shared by all users (portable)
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

  home.file.".config/opencode/opencode.json".source = ../config/opencode/opencode.json;
  home.file.".config/opencode/opencode-notifier.json".source =
    ../config/opencode/opencode-notifier.json;
  home.file.".config/opencode/AGENTS.md".source = ../config/opencode/AGENTS.md;
  home.file.".config/opencode/agent/git-detective.md".source =
    ../config/opencode/agent/git-detective.md;

  # btop writes its own config from the settings below; force overwrite any
  # pre-existing on-disk config so the declarative settings win.
  xdg.configFile."btop/btop.conf".force = true;

  programs = {
    # Shell and CLI tools
    helix.enable = true;

    lazygit.enable = true;
    gitui.enable = true;

    zellij = {
      enable = true;
      enableFishIntegration = true;
      exitShellOnExit = true;
    };

    # Shared git config across Linux and Darwin. Platform-specific bits (e.g.
    # the Linux libsecret credential helper) are merged in from the per-host
    # home configs via additional `programs.git.settings` blocks.
    git = {
      enable = true;
      package = pkgs.gitFull;
      lfs.enable = true;
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
      };
    };

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
      shellAliases =
        {
          htop = "btop";
        }
        # `shutdown` via systemctl is Linux-only.
        // lib.optionalAttrs pkgs.stdenv.isLinux {
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
        bun.symbol = " ";
        c.symbol = " ";
        cmake.symbol = "△ ";
        cmd_duration = {
          disabled = false;
          format = "took [$duration]($style)";
          min_time = 1;
        };
        conda.symbol = " ";
        crystal.symbol = " ";
        dart.symbol = " ";
        deno.symbol = " ";
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
        docker_context.symbol = " ";
        elixir.symbol = " ";
        elm.symbol = " ";
        fennel.symbol = " ";
        fossil_branch.symbol = " ";
        git_branch.symbol = " ";
        gcloud.symbol = " ";
        golang.symbol = " ";
        guix_shell.symbol = " ";
        haskell.symbol = " ";
        haxe.symbol = " ";
        hg_branch.symbol = " ";
        hostname = {
          disabled = false;
          format = "[$hostname]($style) in ";
          ssh_only = false;
          ssh_symbol = " ";
          style = "bold dimmed red";
        };
        java.symbol = " ";
        julia.symbol = " ";
        kotlin.symbol = " ";
        kubernetes.symbol = "󱃾 ";
        lua.symbol = " ";
        maven.symbol = " ";
        memory_usage.symbol = "󰍛 ";
        meson.symbol = "󰔷 ";
        nim.symbol = "󰆥 ";
        mojo.symbol = "🔥 ";
        nix_shell.symbol = " ";
        nodejs.symbol = " ";
        ocaml.symbol = " ";
        package.symbol = "󰏗 ";
        perl.symbol = " ";
        php.symbol = " ";
        pijul_channel.symbol = " ";
        python.symbol = " ";
        rlang.symbol = "󰟔 ";
        ruby.symbol = " ";
        rust.symbol = " ";
        scala.symbol = " ";
        scan_timeout = 10;
        status = {
          disabled = false;
          map_symbol = true;
        };
        sudo = {
          disabled = false;
          symbol = " ";
        };
        swift.symbol = " ";
        terraform.symbol = "󱁢 ";
        username = {
          format = " [$user]($style)@";
          show_always = true;
          style_root = "bold red";
          style_user = "bold red";
        };
        zig.symbol = " ";
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
