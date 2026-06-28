{
  inputs,
  lib,
  ...
}: {
  easy-hosts = {
    autoConstruct = true;
    path = ../hosts;

    # specialArgs that the user/home modules expect, in addition to the
    # `inputs`/`self` easy-hosts injects automatically. dolphin-overlay is
    # nixos-only but harmless to pass to darwin (it is simply unused there).
    shared.specialArgs = {
      inherit (inputs) dolphin-overlay home-manager nix-index-database;
    };

    # Modules split by class so the Darwin host never imports the nixos-only
    # common stack (home-manager.nixosModules, nur, sops-nix, common-base, ...).
    perClass = class: {
      modules =
        if class == "darwin"
        then [
          inputs.determinate.darwinModules.default
          inputs.home-manager.darwinModules.home-manager
          inputs.paneru.darwinModules.paneru
          ../modules/darwin/common.nix
        ]
        else [
          inputs.nur.modules.nixos.default
          inputs.home-manager.nixosModules.home-manager
          inputs.dms-plugin-registry.nixosModules.default
          inputs.determinate.nixosModules.default
          inputs.sops-nix.nixosModules.sops
          ../modules/dreamingoptimal
          ../modules/nix-file-overlay
          ../hosts/common-base.nix
        ];
    };

    # x86_64 Linux hosts get the x86-only base (boot/graphics/steam + wifi).
    perArch = arch: {
      modules = lib.optionals (arch == "x86_64") [
        ../hosts/common-x86.nix
      ];
    };

    # Per-host extras + facter (only DreamingDesk/DreamingBlade have facter.json).
    hosts = {
      DreamingDesk.modules = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ../hosts/x86_64-nixos/DreamingDesk/facter.json;}
        ../modules/users/riccardo.nix
      ];

      DreamingBlade.modules = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ../hosts/x86_64-nixos/DreamingBlade/facter.json;}
        inputs.razer-laptop-controller.nixosModules.default
        {
          powerManagement = {
            enable = true;
            powertop.enable = true;
          };
        }
        ../modules/core/campus-switch.nix
        ../modules/programs/virtualization/waydroid.nix
      ];

      DreamingWork.modules = [
        inputs.apple-silicon.nixosModules.apple-silicon-support
        ../modules/programs/pwa-apps.nix
      ];
    };
  };
}
