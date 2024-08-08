{ config, pkgs, ... }:
   {
     services.envfs.enable = true;
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

     services.pipewire = {
       enable = true;
       alsa.enable = true;
       alsa.support32Bit = true;
       pulse.enable = true;
       jack.enable = true;
     };

     virtualisation.docker.enable = true;
     virtualisation.libvirtd.enable = true;
   }
