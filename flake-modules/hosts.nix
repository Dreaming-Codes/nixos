{
  inputs,
  lib,
  ...
}: let
  # Auto-discover every NixOS/Darwin module file under ../modules via haumea,
  # so adding a module never requires editing an import list. loaders.path
  # yields file *paths* (NixOS imports them lazily and dedupes by path, so the
  # group default.nix files re-importing their siblings is harmless).
  moduleTree = inputs.haumea.lib.load {
    src = ../modules;
    loader = inputs.haumea.lib.loaders.path;
  };
  allModulePaths = lib.collect builtins.isPath moduleTree;

  isUnder = dir: p: lib.hasPrefix (toString (../modules + "/${dir}")) (toString p);

  # Darwin-only modules live under modules/darwin/. The HM module under
  # nix-file-overlay/ is a Home-Manager module, not a NixOS one.
  isDarwinModule = isUnder "darwin";
  isHmModule = p: lib.hasSuffix "/nix-file-overlay/hm-module.nix" (toString p);

  nixosFeatureModules = builtins.filter (p: !(isDarwinModule p) && !(isHmModule p)) allModulePaths;
  darwinFeatureModules = builtins.filter isDarwinModule allModulePaths;
in {
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
    # common stack. Every host imports the FULL dreaming.* module set for its
    # class (auto-discovered above); hosts/common-base.nix + per-host files
    # select features via dreaming.* toggles, not by editing import lists.
    perClass = class: {
      modules =
        if class == "darwin"
        then
          [
            inputs.determinate.darwinModules.default
            inputs.home-manager.darwinModules.home-manager
            inputs.paneru.darwinModules.paneru
          ]
          ++ darwinFeatureModules
        else
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
        {
          powerManagement = {
            enable = true;
            powertop.enable = true;
          };
        }
      ];

      DreamingWork.modules = [
        inputs.apple-silicon.nixosModules.apple-silicon-support
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
        {dreaming.work.enable = true;}
      ];
    };
  };
}
