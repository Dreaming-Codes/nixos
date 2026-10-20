{
  inputs,
  lib,
  ...
}: let
  # Auto-discover every NixOS module file under ../modules via haumea,
  # so adding a module never requires editing an import list. loaders.path
  # yields file *paths* (NixOS imports them lazily and dedupes by path, so the
  # group default.nix files re-importing their siblings is harmless).
  moduleTree = inputs.haumea.lib.load {
    src = ../modules;
    loader = inputs.haumea.lib.loaders.path;
  };
  allModulePaths = lib.collect builtins.isPath moduleTree;

  # The HM module under nix-file-overlay/ is a Home-Manager module, not a NixOS one.
  isHmModule = p: lib.hasSuffix "/nix-file-overlay/hm-module.nix" (toString p);

  nixosFeatureModules = builtins.filter (p: !(isHmModule p)) allModulePaths;
in {
  easy-hosts = {
    autoConstruct = true;
    path = ../hosts;

    # specialArgs that the user/home modules expect, in addition to the
    # `inputs`/`self` easy-hosts injects automatically.
    shared.specialArgs = {
      inherit (inputs) dolphin-overlay home-manager nix-index-database;
    };

    # Every host imports the FULL dreaming.* module set (auto-discovered above);
    # hosts/common-base.nix + per-host files select features via dreaming.*
    # toggles, not by editing import lists.
    perClass = _class: {
      modules =
        [
          inputs.nur.modules.nixos.default
          inputs.home-manager.nixosModules.home-manager
          inputs.dms-plugin-registry.nixosModules.default
          inputs.determinate.nixosModules.default
          inputs.sops-nix.nixosModules.sops

          ../hosts/common-base.nix
        ]
        ++ nixosFeatureModules;
    };

    # x86_64 Linux hosts get the x86-only base (wifi + games toggles). aarch64
    # (Asahi) hosts manage boot/graphics themselves and disable those feature
    # modules in their own host file.
    perArch = arch: {
      modules = lib.optionals (arch == "x86_64") [
        ../hosts/common-x86.nix
      ];
    };

    # Per-host extras + facter (Desk/Blade/WorkDell have facter.json).
    hosts = {
      DreamingDesk.modules = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ../hosts/x86_64-nixos/DreamingDesk/facter.json;}
        {dreaming.users.riccardo.enable = true;}
      ];

      DreamingBlade.modules = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ../hosts/x86_64-nixos/DreamingBlade/facter.json;}
        inputs.razer-laptop-controller.nixosModules.default
        ../hosts/common-laptop.nix
      ];

      DreamingWork.modules = [
        inputs.apple-silicon.nixosModules.apple-silicon-support
        ../hosts/common-laptop.nix
        {dreaming.programs.pwaApps.enable = true;}
        {dreaming.work.enable = true;}
      ];

      # The Dell is provisioned fresh via disko (declarative disk layout in its
      # disk-config.nix). The other hosts were installed manually and keep their
      # by-uuid fileSystems.
      DreamingWorkDell.modules = [
        inputs.disko.nixosModules.disko
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ../hosts/x86_64-nixos/DreamingWorkDell/facter.json;}
        ../hosts/common-laptop.nix
        {dreaming.work.enable = true;}
        # aarch64 emulation so this x86 box can cross-build Raspberry Pi images/tools via QEMU binfmt.
        {boot.binfmt.emulatedSystems = ["aarch64-linux"];}
      ];

      # Same role as the Dell. facter.json is wired only once generated on the machine.
      DreamingWorkGalaxyBook.modules = let
        facterReport = ../hosts/x86_64-nixos/DreamingWorkGalaxyBook/facter.json;
      in
        [
          inputs.disko.nixosModules.disko
          ../hosts/common-laptop.nix
          {dreaming.work.enable = true;}
          {boot.binfmt.emulatedSystems = ["aarch64-linux"];}
        ]
        ++ lib.optionals (builtins.pathExists facterReport) [
          inputs.nixos-facter-modules.nixosModules.facter
          {facter.reportPath = facterReport;}
        ];
    };
  };
}
