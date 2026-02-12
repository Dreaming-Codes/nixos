{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.tmp;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.mergerfs];

    systemd.mounts = [
      {
        where = "/run/tmp-ram";
        what = "tmpfs";
        type = "tmpfs";
        mountConfig.Options = "mode=1777,strictatime,rw,nosuid,nodev,size=1G";
        unitConfig = {
          DefaultDependencies = false;
          ConditionPathIsSymbolicLink = "!/tmp";
        };
      }
      {
        where = "/tmp";
        what = "/run/tmp-ram:/var/tmp/overflow";
        type = "fuse.mergerfs";
        mountConfig.Options = lib.concatStringsSep "," [
          "category.create=epff"
          "minfreespace=200M"
          "moveonenospc=true"
          "dropcacheonclose=true"
          "cache.files=partial"
          "nonempty"
          "allow_other"
        ];
        unitConfig = {
          DefaultDependencies = false;
          ConditionPathIsSymbolicLink = "!/tmp";
          Requires = "run-tmp\\x2dram.mount";
          After = "run-tmp\\x2dram.mount";
        };
      }
    ];

    systemd.tmpfiles.rules = [
      "D /var/tmp/overflow 1777 root root 0"
    ];

    systemd.services.tmp-overflow-monitor = {
      description = "Move closed oversized files from tmpfs to disk overflow";
      after = [
        "tmp.mount"
        "run-tmp\\x2dram.mount"
      ];
      requires = [
        "tmp.mount"
        "run-tmp\\x2dram.mount"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "tmp-overflow-monitor" ''
          set -euo pipefail
          RAM="/run/tmp-ram"
          DISK="/var/tmp/overflow"
          THRESHOLD=$((200 * 1024))

          ${pkgs.findutils}/bin/find "$RAM" -maxdepth 3 -type f -size +200M 2>/dev/null | while IFS= read -r src; do
            ${pkgs.util-linux}/bin/fuser "$src" >/dev/null 2>&1 && continue
            rel="''${src#$RAM/}"
            dest="$DISK/$rel"
            ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dest")"
            ${pkgs.coreutils}/bin/mv "$src" "$dest" 2>/dev/null || continue
            echo "Moved oversized file to disk: $rel"
          done

          for dir in "$RAM"/*/; do
            [ -d "$dir" ] || continue
            size=$(${pkgs.coreutils}/bin/du -sk "$dir" 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1)
            [ "''${size:-0}" -le "$THRESHOLD" ] && continue
            open=0
            while IFS= read -r f; do
              if ${pkgs.util-linux}/bin/fuser "$f" >/dev/null 2>&1; then
                open=1
                break
              fi
            done < <(${pkgs.findutils}/bin/find "$dir" -type f 2>/dev/null)
            [ "$open" -eq 1 ] && continue
            rel="''${dir#$RAM/}"
            rel="''${rel%/}"
            ${pkgs.coreutils}/bin/mkdir -p "$DISK/$rel"
            ${pkgs.coreutils}/bin/mv "$dir"/* "$DISK/$rel/" 2>/dev/null && ${pkgs.coreutils}/bin/rmdir "$dir" 2>/dev/null
            echo "Moved oversized directory to disk: $rel (''${size}KB)"
          done
        '';
      };
    };

    systemd.timers.tmp-overflow-monitor = {
      description = "Periodically check tmpfs for oversized files";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "10s";
        AccuracySec = "5s";
      };
    };
  };
}
