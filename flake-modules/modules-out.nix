{
  inputs,
  lib,
  ...
}: let
  # Auto-discover modules so the public module exports never drift from disk.
  moduleTree = inputs.haumea.lib.load {
    src = ../modules;
    loader = inputs.haumea.lib.loaders.path;
  };
  allModulePaths = lib.collect builtins.isPath moduleTree;

  isUnder = dir: p: lib.hasPrefix (toString (../modules + "/${dir}")) (toString p);
  isHmModule = p: lib.hasSuffix "/nix-file-overlay/hm-module.nix" (toString p);

  # Derive a flat export name from a module path, e.g.
  #   modules/optimization/ram.nix      -> "optimization-ram"
  #   modules/optimization/default.nix  -> "optimization"
  #   modules/core/nix.nix              -> "core-nix"
  exportName = p: let
    rel = lib.removePrefix (toString ../modules + "/") (toString p);
    noExt = lib.removeSuffix ".nix" rel;
    segments = lib.splitString "/" noExt;
    # Drop a trailing "default" segment so a group's default.nix exports as the
    # bare group name.
    trimmed =
      if lib.last segments == "default"
      then lib.init segments
      else segments;
  in
    lib.concatStringsSep "-" trimmed;

  toModuleSet = paths: lib.listToAttrs (map (p: lib.nameValuePair (exportName p) p) paths);

  nixosModulePaths = builtins.filter (p: !(isUnder "darwin" p) && !(isHmModule p)) allModulePaths;
  darwinModulePaths = builtins.filter (isUnder "darwin") allModulePaths;
  hmModulePaths = builtins.filter isHmModule allModulePaths;
in {
  flake.nixosModules = toModuleSet nixosModulePaths;
  flake.darwinModules = toModuleSet darwinModulePaths;
  flake.hmModules = toModuleSet hmModulePaths;
}
