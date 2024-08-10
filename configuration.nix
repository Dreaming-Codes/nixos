{ config, pkgs, inputs, ... }:
   let
     home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/master.tar.gz";
   in
   {
     imports =
       [ "${home-manager}/nixos"
         /etc/nixos/hardware-configuration.nix
         ./modules/networking.nix
         ./modules/services.nix
         ./modules/system.nix
         ./modules/user.nix
         ./modules/home-manager.nix
         ./modules/systemPrograms.nix
         ./modules/starship.nix
         ./misc/sdks.nix
         ./modules/steam.nix
         ./modules/optimization.nix
       ];
   }
