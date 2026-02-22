{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.nix-file-overlay;
  pkg = pkgs.callPackage ../../packages/nix-file-overlay {};

  selfPrefix = toString ../..;

  isUserPath = path: lib.hasPrefix selfPrefix path;
  stripSelfPrefix = path: lib.removePrefix (selfPrefix + "/") path;

  isFromRepo = source: lib.hasPrefix selfPrefix (toString source);
  stripSelf = source: lib.removePrefix (selfPrefix + "/") (toString source);

  # Strip Nix string context to avoid builtins.derivation warnings when
  # store paths are embedded in JSON via writeText. The mapping files are
  # purely informational metadata — they don't need to track store references.
  noCtx = builtins.unsafeDiscardStringContext;

  # ── etc mapping ─────────────────────────────────────────────────────
  etcDefs = options.environment.etc.definitionsWithLocations;
  etcSourceIndex =
    lib.foldl' (
      acc: def:
        lib.foldl' (acc2: key: acc2 // {${key} = (acc2.${key} or []) ++ [def.file];}) acc (
          builtins.attrNames def.value
        )
    ) {}
    etcDefs;

  userEtcEntries = lib.filterAttrs (
    name: _: builtins.any isUserPath (etcSourceIndex.${name} or [])
  ) (lib.filterAttrs (_: v: v.enable) config.environment.etc);

  etcMapping =
    lib.mapAttrs (name: v: {
      path = "/etc/${v.target}";
      source = noCtx (toString v.source);
      definedIn = map noCtx (etcSourceIndex.${name} or []);
      userDefinedIn = map (p: noCtx (stripSelfPrefix p)) (
        builtins.filter isUserPath (etcSourceIndex.${name} or [])
      );
    })
    userEtcEntries;

  etcMappingJson = pkgs.writeText "etc-mapping.json" (builtins.toJSON etcMapping);

  # ── per-user home.file mapping (generated here to avoid HM circular dep) ──
  mkHmMapping = user: let
    hmFiles = lib.filterAttrs (_: v: v.enable) config.home-manager.users.${user}.home.file;
  in
    lib.mapAttrs (
      _name: v:
        {
          target = v.target;
          source = noCtx (toString v.source);
          recursive = v.recursive;
        }
        // (
          if isFromRepo v.source
          then {
            repoRelative = noCtx (stripSelf v.source);
            type = "repo-source";
          }
          else {
            type = "generated";
          }
        )
    )
    hmFiles;

  mkHmMappingJson = user: pkgs.writeText "hm-mapping-${user}.json" (builtins.toJSON (mkHmMapping user));
in {
  options.nix-file-overlay = {
    enable = lib.mkEnableOption "nix-file-overlay system service for temporary file overrides";

    systemRepoPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the system NixOS configuration repository.
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        List of usernames with nix-file-overlay enabled.
        Used by the systemd restore service, activation scripts,
        and to generate per-user home.file mappings.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Deploy mappings via activation script (NOT environment.etc) to avoid
    # circular dependency: we read options.environment.etc.definitionsWithLocations
    # and config.home-manager.users.*.home.file, so we can't write to those.
    system.activationScripts.nix-file-overlay-mappings = lib.stringAfter ["etc"] ''
      mkdir -p /etc/nix-file-overlay
      ln -sf ${etcMappingJson} /etc/nix-file-overlay/etc-mapping.json
      ${lib.concatMapStringsSep "\n" (user: ''
          ln -sf ${mkHmMappingJson user} /etc/nix-file-overlay/hm-mapping-${user}.json
        '')
        cfg.users}
    '';

    # Systemd service to restore persistent overlays on boot
    systemd.services.nix-file-overlay-restore = {
      description = "Restore persistent nix-file-overlay bind mounts";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Restore system overlays
        if [ -f /var/lib/nix-file-overlay/registry.json ]; then
          ${pkg}/bin/nix-file-overlay --restore --registry /var/lib/nix-file-overlay/registry.json || true
        fi

        # Restore user overlays for enrolled users
        ${lib.concatMapStringsSep "\n" (
            user: let
              home = config.users.users.${user}.home;
            in ''
              if [ -f "${home}/.local/share/nix-file-overlay/registry.json" ]; then
                ${pkg}/bin/nix-file-overlay --restore --registry "${home}/.local/share/nix-file-overlay/registry.json" || true
              fi
            ''
          )
          cfg.users}
      '';
    };

    # Activation: warn about active overlays during rebuild
    system.activationScripts.nix-file-overlay-warn = lib.stringAfter ["nix-file-overlay-mappings"] ''
      found=0
      if [ -f /var/lib/nix-file-overlay/registry.json ]; then
        echo -e "\033[1;33m[nix-file-overlay] WARNING: Active system overlays detected\033[0m"
        found=1
      fi
      ${lib.concatMapStringsSep "\n" (
          user: let
            home = config.users.users.${user}.home;
          in ''
            if [ -f "${home}/.local/share/nix-file-overlay/registry.json" ]; then
              echo -e "\033[1;33m[nix-file-overlay] WARNING: Active overlays for user ${user}\033[0m"
              found=1
            fi
          ''
        )
        cfg.users}
      if [ "$found" = "1" ]; then
        echo "  Run 'nix-file-overlay -l' to list or '-a <path>' to apply them."
      fi
    '';

    # Activation: re-apply overlays after rebuild deploys new files
    system.activationScripts.nix-file-overlay-restore = lib.stringAfter ["nix-file-overlay-warn"] ''
      if [ -f /var/lib/nix-file-overlay/registry.json ]; then
        ${pkg}/bin/nix-file-overlay --restore --registry /var/lib/nix-file-overlay/registry.json 2>/dev/null || true
      fi
      ${lib.concatMapStringsSep "\n" (
          user: let
            home = config.users.users.${user}.home;
          in ''
            if [ -f "${home}/.local/share/nix-file-overlay/registry.json" ]; then
              ${pkg}/bin/nix-file-overlay --restore --registry "${home}/.local/share/nix-file-overlay/registry.json" 2>/dev/null || true
            fi
          ''
        )
        cfg.users}
    '';
  };
}
