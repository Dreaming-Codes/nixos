{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.nix-file-overlay;
  pkg = pkgs.callPackage ../../packages/nix-file-overlay {};

  wrappedBin = pkgs.writeShellScriptBin "nix-file-overlay" ''
    ${lib.optionalString (cfg.repoPath != null) ''export NIX_FILE_OVERLAY_USER_REPO="${cfg.repoPath}"''}
    ${lib.optionalString (
      cfg.systemRepoPath != null
    ) ''export NIX_FILE_OVERLAY_SYSTEM_REPO="${cfg.systemRepoPath}"''}
    ${lib.optionalString (cfg.editor != null) ''export NIX_FILE_OVERLAY_EDITOR="${cfg.editor}"''}
    ${
      if cfg.applyCommand == ""
      then ''export NIX_FILE_OVERLAY_CMD=""''
      else lib.optionalString (cfg.applyCommand != null) ''export NIX_FILE_OVERLAY_CMD="${cfg.applyCommand}"''
    }
    exec ${pkg}/bin/nix-file-overlay "$@"
  '';
in {
  options.programs.nix-file-overlay = {
    enable = lib.mkEnableOption "nix-file-overlay file overlay tool";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkg;
      description = "The nix-file-overlay package to use.";
    };

    repoPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to user's config repo (for ~/... files). Defaults to ~/.nixos.";
    };

    systemRepoPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to system NixOS config repo (for /etc/... files).
        Set this or let the NixOS module propagate it.
      '';
    };

    editor = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Editor for post-overlay editing. Defaults to $EDITOR, then vi.";
    };

    applyCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Command for apply-mode fallback when file doesn't trace to config/.
        null: auto-detect opencode. "": guidance only. Other: custom command.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [wrappedBin];
  };
}
