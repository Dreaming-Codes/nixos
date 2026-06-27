{
  pkgs,
  lib,
  config,
  ...
}: let
  opencode = pkgs.writeShellScriptBin "opencode" ''
    exec ${pkgs.bun}/bin/bunx opencode-ai@latest "$@"
  '';
in {
  home.stateVersion = "26.05";

  home.shell.enableShellIntegration = true;
  programs.home-manager.enable = true;

  home.packages = [
    pkgs.git-spice
  ];

  home.activation.gitSigningIfAvailable = lib.hm.dag.entryAfter ["writeBoundary"] ''
    signing_config="${config.xdg.configHome}/git/signing-if-available"
    mkdir -p "$(dirname "$signing_config")"

    if ${pkgs.gnupg}/bin/gpg --batch --list-secret-keys 1FE3A3F18110DDDD >/dev/null 2>&1; then
      printf '[commit]\n\tgpgSign = true\n' > "$signing_config"
    else
      printf '[commit]\n\tgpgSign = false\n' > "$signing_config"
    fi
  '';

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

  # Ensure the SSH ControlPath socket directory exists for connection multiplexing.
  home.file.".ssh/sockets/.keep".text = "";

  home.file.".config/opencode/opencode-notifier.json".source =
    ../config/opencode/opencode-notifier.json;

  programs.opencode = {
    enable = true;
    package = opencode;
    context = ../config/opencode/AGENTS.md;
    agents.git-detective = ../config/opencode/agent/git-detective.md;
    settings = {
      permission = {
        "*" = "allow";
        external_directory = "allow";
        bash = {
          "*" = "allow";
          "git push *" = "ask";
          "git push" = "ask";
          "gh pr create *" = "ask";
          "gh pr edit *" = "ask";
          "gh pr merge *" = "ask";
          "gh pr close *" = "ask";
          "glab mr create *" = "ask";
          "glab mr update *" = "ask";
          "glab mr merge *" = "ask";
          "glab mr close *" = "ask";
          "terraform apply*" = "ask";
          "terraform destroy*" = "ask";
          "terraform import*" = "ask";
        };
      };
      provider.amazon-bedrock.options = {
        region = "us-west-2";
        profile = "BedrockAccess";
        timeout = 600000;
      };
      plugin = ["@mohak34/opencode-notifier@latest"];
      agent = {
        build.model = "amazon-bedrock/anthropic.claude-opus-4-8";
        explore.model = "amazon-bedrock/anthropic.claude-opus-4-8";
      };
      lsp.rust = {
        command = ["rust-analyzer"];
        initialization.rust-analyzer.check.command = "clippy";
      };
    };
  };

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
      };
      settings = {
        include = {
          path = "${config.xdg.configHome}/git/signing-if-available";
        };
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

        # Dimmer direnv output
        set -gx DIRENV_LOG_FORMAT (printf '\033[22m\033[2mdirenv: %%s\033[0m\033[22m')

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
          echo "║  COMPOSITOR (niri)                                           ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Super+Space    Open terminal (rio)                           ║"
          echo "║  Super+W        Open browser (brave)                          ║"
           echo "║  Super+X        Open DMS Spotlight                            ║"
          echo "║  Super+Q        Close window                                  ║"
          echo "║  Super+F        Fullscreen                                    ║"
          echo "║  Super+O        Toggle floating                               ║"
          echo "║  Super+C        Clipboard (DMS)                               ║"
          echo "║  Super+L        Lock screen                                   ║"
          echo "║  Super+Tab      Overview                                      ║"
          echo "║  Super+Slash    Keybinds overlay                              ║"
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
          echo "║  Super+Arrow/hjkl   Move focus                               ║"
          echo "║  Super+Shift+Arrow  Move window/column                       ║"
          echo "║  Super+Ctrl+Arrow   Focus monitor                            ║"
          echo "║  Super+R            Cycle column width preset                ║"
          echo "║  Super+-/=          Shrink/grow column width                 ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  WORKSPACES                                                   ║"
          echo "╠═══════════════════════════════════════════════════════════════╣"
          echo "║  Super+1-0      Switch to workspace 1-10                      ║"
          echo "║  Super+Shift+1-0  Move column to workspace 1-10               ║"
          echo "║  Super+U/I      Focus workspace down/up                       ║"
          echo "║  Super+Page Dn/Up  Focus workspace down/up                    ║"
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
        aws.disabled = true;
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
      # Silence the "taking too long" warning when flakes re-evaluate.
      config.global.warn_timeout = "0";
    };

    # Reuse a single SSH connection within a short window so rapid successive
    # git operations skip repeated TCP/TLS/auth handshakes
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      # Marker the sw repo's nix develop shellHook greps for to decide whether
      # to nag about running nlk_sw_setup.sh. The useful bits are already
      # replicated declaratively, so this comment alone silences the banner.
      extraConfig = "# nlk_speed_up_git";
      matchBlocks."*" = {
        controlMaster = "auto";
        controlPath = "~/.ssh/sockets/%r@%h-%p";
        controlPersist = "15s";
      };
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
      options = ["--cmd cd"];
    };
  };
}
