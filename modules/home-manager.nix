{ config, pkgs, lib, ... }:
   {
     home-manager.users.dreamingcodes = {
       home.stateVersion = "24.11";
       home.packages = with pkgs; [
         kdePackages.kate
         zed-editor
         brave
         telegram-desktop
         bitwarden
         vesktop
         prismlauncher
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
         tor-browser
         jetbrains-toolbox
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
   }
