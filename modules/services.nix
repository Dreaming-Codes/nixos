{
  config,
  pkgs,
  inputs,
  ...
}: let
  nixos-auto-update = pkgs.writeShellScriptBin "nixos-auto-update" ''
    set -euo pipefail

    CONFIG_DIR="/home/dreamingcodes/.nixos"
    STATE_FILE="/var/lib/nixos-auto-update/last-update-week"
    CURRENT_WEEK=$(date +%G-%V)

    # Send notification to all logged-in users
    notify_users() {
      local title="$1"
      local message="$2"
      local urgency="''${3:-normal}"
      
      for user in $(who | awk '{print $1}' | sort -u); do
        uid=$(id -u "$user" 2>/dev/null) || continue
        # Check if user's D-Bus session bus exists before attempting notification
        if [ -S "/run/user/$uid/bus" ]; then
          sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            ${pkgs.libnotify}/bin/notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
        fi
      done
    }

    # Check if we already updated this week
    if [ -f "$STATE_FILE" ]; then
      LAST_UPDATE_WEEK=$(cat "$STATE_FILE")
      if [ "$CURRENT_WEEK" = "$LAST_UPDATE_WEEK" ]; then
        echo "Already updated this week ($CURRENT_WEEK). Skipping."
        exit 0
      fi
    fi

    # Check if today is Sunday or later in the week (we update on first boot after Sunday)
    # Day of week: 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    DAY_OF_WEEK=$(date +%w)
    
    # We want to update on Sunday (0) or any day after if we haven't updated this week yet
    # Since we already checked if we updated this week, we can proceed
    
    notify_users "NixOS Auto-Update" "Starting weekly system update..." "low"
    echo "Starting NixOS auto-update for week $CURRENT_WEEK..."

    cd "$CONFIG_DIR"

    # Mark directory as safe for git (running as root on user-owned dir)
    git config --global --add safe.directory "$CONFIG_DIR" 2>/dev/null || true

    # Fetch and check for remote changes
    echo "Fetching remote..."
    git fetch origin

    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)

    if [ "$LOCAL" = "$REMOTE" ]; then
      echo "Already up to date with remote."
      mkdir -p "$(dirname "$STATE_FILE")"
      echo "$CURRENT_WEEK" > "$STATE_FILE"
      notify_users "NixOS Auto-Update" "System already up to date." "low"
      exit 0
    fi

    # Check for uncommitted changes - if any, abort (don't want to mess with user's work)
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Uncommitted changes detected. Skipping auto-update to avoid conflicts."
      notify_users "NixOS Auto-Update" "Skipped: uncommitted changes in config repo." "normal"
      exit 0
    fi

    # Pull changes
    echo "Pulling latest changes..."
    if ! git pull --ff-only origin main 2>/dev/null && ! git pull --ff-only origin master 2>/dev/null; then
      echo "Pull failed (likely conflicts or non-fast-forward). Skipping."
      notify_users "NixOS Auto-Update" "Failed: could not pull changes (conflicts?)." "critical"
      exit 1
    fi

    echo "Applying configuration for next boot..."
    HOSTNAME=$(${pkgs.hostname}/bin/hostname)
    if nixos-rebuild boot --flake "$CONFIG_DIR#$HOSTNAME" --impure --accept-flake-config; then
      mkdir -p "$(dirname "$STATE_FILE")"
      echo "$CURRENT_WEEK" > "$STATE_FILE"
      notify_users "NixOS Auto-Update" "Update complete! Changes will apply on next reboot." "normal"
      echo "Update successful! Configuration will be applied on next boot."
    else
      notify_users "NixOS Auto-Update" "Failed to apply configuration." "critical"
      echo "Failed to apply configuration."
      exit 1
    fi
  '';
in {
  services.envfs.enable = true;

  # NixOS auto-update service (runs on boot, applies weekly updates)
  systemd.services.nixos-auto-update = {
    description = "NixOS Weekly Auto-Update";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.git pkgs.sudo pkgs.gawk pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${nixos-auto-update}/bin/nixos-auto-update";
      StateDirectory = "nixos-auto-update";
      # Run as root since we need to apply system configuration
      User = "root";
      # Give it some time to complete
      TimeoutStartSec = "30min";
    };
  };
  services.xserver.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  # Default session for dreamingcodes (and system-wide fallback)
  services.displayManager.defaultSession = "hyprland";

  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [konsole];

  programs.hyprland = {
    enable = true;
  };
  programs.hyprlock.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "alt-intl";
  };

  services.printing = {
    enable = true;
    drivers = [
      pkgs.hplipWithPlugin
    ];
  };

  # Centralized storage for coredumps (coredumpctl list)
  systemd.coredump.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    systemWide = false;
    wireplumber.enable = true;
  };

  virtualisation = {
    docker.enable = true;
    spiceUSBRedirection.enable = true;
  };

  environment.etc = {
    # https://github.com/Scrut1ny/Hypervisor-Phantom
    "ovmf" = {
      source = ./ovmf;
    };
  };
}
