{ config, pkgs, ... }:
   {
     programs.fish.enable = true;
     # Partition-manager does not work if not installed globally
     programs.partition-manager.enable = true;
     programs.nix-ld.enable = true;
     # Adb need to be installed globally to run as root
     programs.adb.enable = true;
     # dconf need to be installed globally to run as root
     programs.dconf.enable = true;
   }
