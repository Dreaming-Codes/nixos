{ config, pkgs, inputs, ... }:
   let
     home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
   in
   {
     imports =
       [ (import "${home-manager}/nixos")
         /etc/nixos/hardware-configuration.nix
       ];

     nix.gc = {
       automatic = true;
       dates = "weekly";
       options = "--delete-older-than 1w";
     };

     nix.settings.auto-optimise-store = true;

     programs.nix-ld.enable = true;
     services.envfs.enable = true;

     nix.settings.experimental-features = [ "nix-command" "flakes" "dynamic-derivations" ];

     boot.loader.systemd-boot.enable = true;
     boot.loader.efi.canTouchEfiVariables = true;

     networking.hostName = "DreamingDesk";
     security.sudo.wheelNeedsPassword = false;
     security.pam.services.login.enableKwallet = true;

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

     services.xserver.enable = false;

     services.displayManager.sddm = {
       enable = true;
       wayland.enable = true;
     };
     services.desktopManager.plasma6.enable = true;
     environment.plasma6.excludePackages = with pkgs.kdePackages; [ konsole ];

     services.xserver.xkb = {
       layout = "us";
       variant = "alt-intl";
     };

     services.printing.enable = true;

     hardware.pulseaudio.enable = false;
     security.rtkit.enable = true;
     services.pipewire = {
       enable = true;
       alsa.enable = true;
       alsa.support32Bit = true;
       pulse.enable = true;
       jack.enable = true;
     };

     virtualisation.docker.enable = true;
     virtualisation.libvirtd.enable = true;

     boot.kernelModules = [ "kvm-intel" ];

     programs.fish.enable = true;
     programs.partition-manager.enable = true;
     programs.adb.enable = true;
     programs.dconf.enable = true;

     users.users.dreamingcodes = {
       isNormalUser = true;
       description = "DreamingCodes";
       extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "kvm" "adbusers" ];
       shell = pkgs.fish;
     };

     home-manager.users.dreamingcodes = {
       home.stateVersion = "18.09";
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
         alacritty
         bun
         nodejs
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
         easyeffects.enable = true;
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
         zellij = {
           enable = true;
           enableBashIntegration = true;
           enableFishIntegration = true;
         };
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
             "$schema" = "https://starship.rs/config-schema.json";
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
             time = {
               format = " 🕙 \$time(\$style)\n";
               time_format = "%T";
               style = "bright-white";
               disabled = true;
             };
             character = {
               success_symbol = " [╰─λ](bold red)";
               error_symbol = " [×](bold red)";
             };
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
             nix_shell = { symbol = " "; };
             haskell = { symbol = " "; };
             hg_branch = { symbol = " "; };
             java = { symbol = " "; };
             julia = { symbol = " "; };
             nim = { symbol = " "; };
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
           enable = true;
           interactiveShellInit = ''
           any-nix-shell fish | source
           '';
           shellAliases = {
             cat = "bat --paging=never";
             htop = "btop";
             shutdown = "systemctl poweroff";
           };
         };
         bash = {
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

     nixpkgs.config.allowUnfree = true;
     hardware.bluetooth.enable = true;

     environment.sessionVariables = rec {
       ZELLIJ_AUTO_EXIT = "true";
     };

     environment.systemPackages = with pkgs; [
       fira-code-nerdfont
       wget
       inputs.kwin-effects-forceblur.packages.${pkgs.system}.default
       any-nix-shell
       inputs.nix-alien.packages.${system}.nix-alien
       temurin-bin
       gcc
       openssl
       pkg-config
     ];

     environment.variables = {
       PKG_CONFIG_PATH="${pkgs.openssl.dev}/lib/pkgconfig";
     };

     networking.firewall =
     {
       allowedTCPPortRanges = [
         { from = 1714; to = 1764; } # KDE Connect
       ];
       allowedUDPPortRanges = [
         { from = 1714; to = 1764; } # KDE Connect
       ];
     };

     system.stateVersion = "24.11";
   }
