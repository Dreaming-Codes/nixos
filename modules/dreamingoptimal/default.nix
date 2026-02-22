{
  inputs,
  lib,
  config,
  ...
}: let
  inherit (lib) mkDefault mkEnableOption mkIf;
  cfg = config.dreamingoptimal.optimization;
in {
  imports = [
    ./ram.nix
    ./tmp.nix
    ./swap-fallback.nix
    ./process-tuning.nix
    ./sysctl.nix
    ./bpftune.nix
    ./cachykernel.nix
    ./fstrim.nix
    ./envfs.nix
  ];

  options.dreamingoptimal.optimization = {
    enable = mkEnableOption "DreamingOptimal optimization profile";

    ram.enable = mkEnableOption "compressed RAM swap (zram)";
    tmp.enable = mkEnableOption "RAM-backed /tmp with disk overflow fallback";
    swapFallback.enable = mkEnableOption "disk swap fallback when zram is exhausted";
    processTuning.enable = mkEnableOption "process priority and OOM tuning";
    sysctl.enable = mkEnableOption "kernel sysctl tuning";
    bpftune.enable = mkEnableOption "bpftune";
    cachykernel.enable = mkEnableOption "CachyOS kernel";
    fstrim.enable = mkEnableOption "periodic SSD TRIM";
    envfs.enable = mkEnableOption "envfs mount timeout fix";
  };

  config = mkIf cfg.enable {
    dreamingoptimal.optimization = {
      ram.enable = mkDefault true;
      tmp.enable = mkDefault true;
      swapFallback.enable = mkDefault true;
      processTuning.enable = mkDefault true;
      sysctl.enable = mkDefault true;
      bpftune.enable = mkDefault true;
      cachykernel.enable = mkDefault true;
      fstrim.enable = mkDefault true;
      envfs.enable = mkDefault true;
    };
  };
}
