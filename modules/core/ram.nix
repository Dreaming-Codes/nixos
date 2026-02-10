{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = [pkgs.mergerfs];

  # /tmp as a mergerfs union of RAM (tmpfs, 1GB cap) + disk overflow.
  # Small/fast writes go to tmpfs; when tmpfs is within 200MB of full,
  # new files are created on disk instead. Completely transparent to
  # all applications. On shutdown we skip unmounting since the tmpfs
  # portion is RAM-backed and disk portion is cleaned on boot.
  systemd.mounts = [
    # 1. RAM-backed branch (1GB cap)
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
    # 2. mergerfs union: RAM branch (preferred) + disk overflow
    {
      where = "/tmp";
      what = "/run/tmp-ram:/var/tmp/overflow";
      type = "fuse.mergerfs";
      mountConfig.Options = lib.concatStringsSep "," [
        "category.create=epff" # use first branch (tmpfs) that has enough space
        "minfreespace=200M" # when <200MB free on a branch, skip it for new files
        "moveonenospc=true" # if a write gets ENOSPC on tmpfs, move file to disk
        "dropcacheonclose=true" # free page cache for files on close
        "cache.files=partial" # cache metadata but not full content
        "nonempty" # allow mounting over existing /tmp
        "allow_other" # let all users access
      ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathIsSymbolicLink = "!/tmp";
        Requires = "run-tmp\\x2dram.mount";
        After = "run-tmp\\x2dram.mount";
      };
    }
  ];

  # Ensure the disk-backed overflow directory exists and is cleaned on boot
  systemd.tmpfiles.rules = [
    "D /var/tmp/overflow 1777 root root 0"
  ];

  # Reclaim RAM by moving closed oversized files/dirs (>200MB) from tmpfs to disk.
  # For open files that grow past tmpfs capacity, mergerfs moveonenospc handles
  # the move transparently (preserving open fds). This monitor is defense-in-depth
  # for files that landed fully on tmpfs and have since been closed.
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
        THRESHOLD=$((200 * 1024)) # 200MB in KB

        # Move individual files larger than 200MB (skip if open)
        ${pkgs.findutils}/bin/find "$RAM" -maxdepth 3 -type f -size +200M 2>/dev/null | while IFS= read -r src; do
          ${pkgs.util-linux}/bin/fuser "$src" >/dev/null 2>&1 && continue
          rel="''${src#$RAM/}"
          dest="$DISK/$rel"
          ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dest")"
          ${pkgs.coreutils}/bin/mv "$src" "$dest" 2>/dev/null || continue
          echo "Moved oversized file to disk: $rel"
        done

        # Move top-level directories larger than 200MB total (skip if any file open)
        for dir in "$RAM"/*/; do
          [ -d "$dir" ] || continue
          size=$(${pkgs.coreutils}/bin/du -sk "$dir" 2>/dev/null | ${pkgs.coreutils}/bin/cut -f1)
          [ "''${size:-0}" -le "$THRESHOLD" ] && continue
          # Skip if any file inside is currently open
          open=0
          while IFS= read -r f; do
            if ${pkgs.util-linux}/bin/fuser "$f" >/dev/null 2>&1; then
              open=1; break
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
}
