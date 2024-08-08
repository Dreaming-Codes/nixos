{ config, pkgs, ... }:
   {
     networking.hostName = "DreamingDesk";
     networking.networkmanager.enable = true;

     networking.firewall = {
       allowedTCPPortRanges = [
         { from = 1714; to = 1764; } # KDE Connect
       ];
       allowedUDPPortRanges = [
         { from = 1714; to = 1764; } # KDE Connect
       ];
     };
   }
