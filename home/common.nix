{
  pkgs,
  lib,
  config,
  ...
}: {
  home.shell.enableShellIntegration = true;
  programs.home-manager.enable = true;

  # Comma integration with nix-index
  programs.nix-index-database.comma.enable = true;

  # Bitwarden SSH agent (path is user-specific via home.homeDirectory)
  home.sessionVariables = {
    SSH_AUTH_SOCK = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
  };

  # Common session paths
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
  ];

  # Config file links shared by all users
  home.file."./.config/zellij" = {
    source = ../config/zellij;
    recursive = true;
  };

  home.file."./.config/wezterm" = {
    source = ../config/wezterm;
    recursive = true;
  };

  home.file."./.config/helix" = {
    source = ../config/helix;
    recursive = true;
  };

  programs = {
    # Shell and CLI tools
    wezterm.enable = true;
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
          echo "║  Super+Space    Open terminal (wezterm)                       ║"
          echo "║  Super+W        Open browser (helium)                         ║"
          echo "║  Super+X        Open Vicinae                                  ║"
          echo "║  Super+Q        Kill active window                            ║"
          echo "║  Super+F        Fullscreen                                    ║"
          echo "║  Super+O        Toggle floating                               ║"
          echo "║  Super+L        Lock screen (hyprlock)                        ║"
          echo "║  Super+M        Toggle mixer                                  ║"
          echo "║  Super+C        Clipboard (vicinae)                           ║"
          echo "║  Super+N        Toggle Obsidian workspace                     ║"
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
          echo "║  Super+,        Previous wallpaper                            ║"
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
        c.symbol = " ";
        cmd_duration = {
          disabled = false;
          format = "took [$duration]($style)";
          min_time = 1;
        };
        conda.symbol = " ";
        crystal.symbol = " ";
        dart.symbol = " ";
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
        lua.symbol = " ";
        memory_usage.symbol = "󰍛 ";
        meson.symbol = "󰔷 ";
        nim.symbol = "󰆥 ";
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
        sudo.disabled = false;
        swift.symbol = " ";
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
      extraOptions = ["-al" "--icons"];
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
