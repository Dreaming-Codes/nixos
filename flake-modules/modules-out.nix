{...}: {
  flake.nixosModules = {
    nix-file-overlay = ../modules/nix-file-overlay;
    dreamingoptimal = ../modules/dreamingoptimal;
    dreamingoptimal-ram = ../modules/dreamingoptimal/ram.nix;
    dreamingoptimal-swap-fallback = ../modules/dreamingoptimal/swap-fallback.nix;
    dreamingoptimal-process-tuning = ../modules/dreamingoptimal/process-tuning.nix;
    dreamingoptimal-sysctl = ../modules/dreamingoptimal/sysctl.nix;
    dreamingoptimal-bpftune = ../modules/dreamingoptimal/bpftune.nix;
    dreamingoptimal-cachykernel = ../modules/dreamingoptimal/cachykernel.nix;
    dreamingoptimal-fstrim = ../modules/dreamingoptimal/fstrim.nix;
    dreamingoptimal-envfs = ../modules/dreamingoptimal/envfs.nix;
  };

  flake.hmModules = {
    nix-file-overlay = ../modules/nix-file-overlay/hm-module.nix;
  };
}
