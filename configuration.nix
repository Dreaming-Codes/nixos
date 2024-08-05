{ config, pkgs, inputs, ... }:
let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
in
{
  imports =
    [ (import "${home-manager}/nixos")
      # Include the results of the hardware scan.
      /etc/nixos/hardware-configuration.nix
    ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 1w";
  };

  nix.settings.auto-optimise-store = true;

  # Support for generic programs
  programs.nix-ld.enable = true;

  # Dynamically populate /bin and /usr/bin
  services.envfs.enable = true;

  # Enable the Flakes feature and the accompanying new nix command-line tool
  nix.settings.experimental-features = [ "nix-command" "flakes" "dynamic-derivations" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "DreamingDesk"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Disable password for sudo
  security.sudo = {
    wheelNeedsPassword = false;
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "it_IT.UTF-8";
    LC_IDENTIFICATION = "it_IT.UTF-8";
    LC_MEASUREMENT = "it_IT.UTF-8";
    LC_MONETARY = "it_IT.UTF-8";
    LC_NAME = "it_IT.UTF-8";
    LC_NUMERIC = "it_IT.UTF-8";
    LC_PAPER = "it_IT.UTF-8";
    LC_TELEPHONE = "it_IT.UTF-8";
    LC_TIME = "it_IT.UTF-8";
  };

  # Disable X11
  services.xserver.enable = false;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm = {
    enable = true;
    wayland = {
      enable = true;
    };
  };
  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
  ];

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      layout = "us";
      variant = "alt-intl";
    };
  };

  # Configure console keymap
  #console = {
  #  useXkbConfig = true; # use xkbOptions in tty.
  #};

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable docker
  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;

  boot.kernelModules = [ "kvm-intel" ];

  # Fish needs to be installed as global program to be set as user shell
  programs.fish.enable = true;

  # For a KDE bug this need some patches to work on nix which are included in the program from nix
  programs.partition-manager.enable = true;

  # Enable adb as root deamon to avoid messing with usb permissions
  programs.adb.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.dreamingcodes = {
    isNormalUser = true;
    description = "DreamingCodes";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "kvm" "adbusers" ];
    shell = pkgs.fish;
  };

  home-manager.users.dreamingcodes = {
    /* The home.stateVersion option does not have a default and must be set */
    home.stateVersion = "18.09";
    /* Here goes the rest of your home-manager config, e.g. home.packages = [ pkgs.foo ]; */
    home.packages = with pkgs; [
      kdePackages.kate
      zed-editor
      brave
      telegram-desktop
      bitwarden
      vesktop
      prismlauncher
      steam
      btop
      jetbrains-toolbox
      alacritty
      bun
      bintools
      rustup
      kdePackages.kleopatra
      gnupg
      pinentry-qt
      fzf
      spotify
      steam-run
      tor-browser
    ];
    services = {
      kdeconnect = {
        enable = true;
        indicator = true;
        package = pkgs.kdePackages.kdeconnect-kde;
      };
      gpg-agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-qt;
      };
    };
    programs = {
      git = {
        enable = true;
        userName = "DreamingCodes";
        userEmail = "me@dreaming.codes";
        signing = {
          key = "1FE3A3F18110DDDD";
          signByDefault = true;
        };
      };
      gitui.enable = true;
      git-credential-oauth.enable = true;
      starship = {
        enable = true;
        settings = {
          # Get editor completions based on the config schema
          "$schema" = "https://starship.rs/config-schema.json";

          # FIRST LINE/ROW: Info & Status
          username = {
            format = " [╭─$user]($style)@";
            style_user = "bold red";
            style_root = "bold red";
            show_always = true;
          };

          hostname = {
            format = "[$hostname]($style) in ";
            style = "bold dimmed red";
            trim_at = "-";
            ssh_only = false;
            disabled = false;
          };

          directory = {
            style = "purple";
            truncation_length = 0;
            truncate_to_repo = true;
            truncation_symbol = "repo: ";
          };

          git_status = {
            style = "white";
            ahead = "⇡\${count}";
            diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
            behind = "⇣\${count}";
            deleted = "x";
          };

          cmd_duration = {
            min_time = 1;
            format = "took [\$duration](\$style)";
            disabled = false;
          };

          # Prompt: optional param 1
          time = {
            format = " 🕙 \$time(\$style)\n";
            time_format = "%T";
            style = "bright-white";
            disabled = true;
          };

          # Prompt: param 2
          character = {
            success_symbol = " [╰─λ](bold red)";
            error_symbol = " [×](bold red)";
          };

          # SYMBOLS
          status = {
            symbol = "🔴";
            format = "[\\[\$symbol\$status_common_meaning\$status_signal_name\$status_maybe_int\\]](\$style)";
            map_symbol = true;
            disabled = false;
          };

          aws = { symbol = " "; };
          conda = { symbol = " "; };
          dart = { symbol = " "; };
          elixir = { symbol = " "; };
          elm = { symbol = " "; };
          git_branch = { symbol = " "; };
          golang = { symbol = " "; };
          haskell = { symbol = " "; };
          hg_branch = { symbol = " "; };
          java = { symbol = " "; };
          julia = { symbol = " "; };
          nim = { symbol = " "; };
          nix_shell = { symbol = " "; };
          nodejs = { symbol = " "; };
          package = { symbol = " "; };
          perl = { symbol = " "; };
          php = { symbol = " "; };
          python = { symbol = " "; };
          ruby = { symbol = " "; };
          rust = { symbol = " "; };
          swift = { symbol = "ﯣ "; };
        };
      };
      fish = {
        # Needed for the home-manager fish integrations to work
        enable = true;
        shellAliases = {
          cat = "bat --paging=never";
          htop = "btop";
          shutdown = "systemctl poweroff";
        };
      };
      bash = {
        # Needed for the home-manager bash integrations to work
        enable = true;
      };
      eza = {
        enable = true;
        extraOptions = [ "-al" "--icons" ];
      };
      bat = {
        enable = true;
      };
      direnv = {
        enable = true;
      };
      zoxide = {
        enable = true;
        options = [
          "--cmd cd"
        ];
      };
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable bluetooth
  hardware.bluetooth.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    fira-code-nerdfont
    wget
    inputs.kwin-effects-forceblur.packages.${pkgs.system}.default
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  networking.firewall =
  {
    allowedTCPPortRanges = [
      { from = 1714; to = 1764; } # KDE Connect
    ];
    allowedUDPPortRanges = [
      { from = 1714; to = 1764; } # KDE Connect
    ];
    #allowedTCPPorts = [];
    #allowedUDPPorts = [];
  };
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
