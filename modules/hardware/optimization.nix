{lib, ...}: {
  config.dreamingoptimal.optimization = {
    ram.enable = lib.mkDefault true;
    swapFallback.enable = lib.mkDefault true;
    processTuning.enable = lib.mkDefault true;
    sysctl.enable = lib.mkDefault true;
    bpftune.enable = lib.mkDefault true;
    cachykernel.enable = lib.mkDefault true;
    fstrim.enable = lib.mkDefault true;
  };
}
