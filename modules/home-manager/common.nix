{
  pkgs,
  lib,
  config,
  ...
}: {
  home.shell.enableShellIntegration = true;
  programs.home-manager.enable = true;

  # Add Flathub remote for user-level Flatpak installations
  # This allows KDE Discover to install apps per-user without requiring admin password
  home.activation.flatpak-user-remote = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.flatpak}/bin/flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  '';

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
    source = ../zellij;
    recursive = true;
  };

  home.file."./.config/wezterm" = {
    source = ../wezterm;
    recursive = true;
  };

  home.file."./.config/helix" = {
    source = ../helix;
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
        # Use bat as cat replacement in interactive shell
        function cat --wraps bat --description 'Use bat instead of cat'
          ${pkgs.bat}/bin/bat $argv
        end
      '';
      shellAliases = {
        htop = "btop";
        shutdown = "systemctl poweroff";
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
