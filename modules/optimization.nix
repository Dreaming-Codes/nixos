{ config, pkgs, ... }: {
  garuda = {
    performance-tweaks = {
      cachyos-kernel = true;
      enable = true;
    };
  };
  chaotic.scx = {
    enable = true;
    scheduler = "scx_rusty";
  };
}
