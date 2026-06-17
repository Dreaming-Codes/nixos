#!/usr/bin/env bash
# DreamingWork — Asahi/aarch64 NixOS ONE-SHOT install.
#
# Run INSIDE the booted nixos-apple-silicon installer (as root), NOT on macOS.
# Assumes a WIRED/already-online connection. Stops only ONCE, to confirm the
# partition to format. After that it runs end-to-end through nixos-install.
#
# Usage on the target:
#   sudo su
#   nix-shell -p git
#   git clone -b asahi-wip https://github.com/Dreaming-Codes/nixos /tmp/nixos
#   bash /tmp/nixos/scripts/asahi-install.sh
#
# Steps: show table -> create root part -> [confirm] -> mkfs -> mount ->
#        generate hw config -> copy Asahi firmware -> local git commit so the
#        flake sees new files -> nixos-install --flake .#DreamingWork

set -euo pipefail

DISK="/dev/nvme0n1"
REPO="$(cd "$(dirname "$0")/.." && pwd)"   # repo root (…/nixos)
HOST="DreamingWork"
HOST_DIR="$REPO/hosts/dreamingwork"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

confirm() { local a; read -r -p "$1 [type YES to proceed]: " a; [ "$a" = "YES" ]; }

[ "$(id -u)" -eq 0 ] || { red "Run as root (sudo su)."; exit 1; }
[ -b "$DISK" ] || { red "$DISK not found — run inside the Linux installer, not macOS."; lsblk || true; exit 1; }

# ---------------------------------------------------------------------------
bold "=== Step 1/9: current partition table on $DISK ==="
sgdisk "$DISK" -p || true
echo
red "We only ADD a root partition in the free space. Partition 1"
red "(iBootSystemContainer) and the last (RecoveryOSContainer) are left alone."

# ---------------------------------------------------------------------------
bold "=== Step 2/9: create root partition (sgdisk -n 0:0 -s) ==="
sgdisk "$DISK" -n 0:0 -s
partprobe "$DISK" 2>/dev/null || true
sleep 1
sgdisk "$DISK" -p

# Detect the new Linux partition: highest-numbered "Linux filesystem"/8300.
ROOT_PART="$(lsblk -rno NAME,PARTTYPENAME "$DISK" 2>/dev/null | awk '/[Ll]inux/ {print "/dev/"$1}' | tail -n1)"
if [ -z "${ROOT_PART:-}" ] || [ ! -b "$ROOT_PART" ]; then
  LASTNUM="$(sgdisk "$DISK" -p | awk '/^[[:space:]]*[0-9]+/{n=$1} END{print n}')"
  ROOT_PART="${DISK}p${LASTNUM}"
fi

echo
bold "Detected new root partition: $ROOT_PART"
red "VERIFY above: it should be the large (~491GB) type-8300 partition you just created."
confirm "Format $ROOT_PART as ext4 (label nixos)? THIS ERASES IT." || { red "Aborted, no changes since partition create."; exit 1; }

# ---------------------------------------------------------------------------
bold "=== Step 3/9: format $ROOT_PART ext4 ==="
mkfs.ext4 -F -L nixos "$ROOT_PART"

# ---------------------------------------------------------------------------
bold "=== Step 4/9: mount root + Asahi EFI partition ==="
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
EFI_PARTUUID="$(cat /proc/device-tree/chosen/asahi,efi-system-partition)"
mount "/dev/disk/by-partuuid/${EFI_PARTUUID}" /mnt/boot
green "Mounted:"; findmnt /mnt; findmnt /mnt/boot

# ---------------------------------------------------------------------------
bold "=== Step 5/9: time sync (wired network assumed) ==="
systemctl restart systemd-timesyncd 2>/dev/null || true
if ! ping -c1 -W3 cache.nixos.org >/dev/null 2>&1; then
  red "WARNING: no network reachable. nixos-install will fail without internet."
  red "Connect ethernet (or run 'iwctl station wlan0 connect SSID') then re-run."
fi

# ---------------------------------------------------------------------------
bold "=== Step 6/9: nixos-generate-config ==="
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix "$HOST_DIR/hardware-configuration.nix"
green "hardware-configuration.nix copied into the flake:"
cat "$HOST_DIR/hardware-configuration.nix"

# ---------------------------------------------------------------------------
bold "=== Step 7/9: copy Asahi peripheral firmware into the flake (pure build) ==="
mkdir -p "$HOST_DIR/firmware"
if cp /mnt/boot/asahi/all_firmware.tar.gz "$HOST_DIR/firmware/" 2>/dev/null; then
  cp /mnt/boot/asahi/kernelcache* "$HOST_DIR/firmware/" 2>/dev/null || true
  green "Firmware copied from /mnt/boot/asahi/:"
  ls -la "$HOST_DIR/firmware/"
else
  red "Could not find /mnt/boot/asahi/all_firmware.tar.gz."
  red "Listing /mnt/boot/asahi for inspection:"; ls -la /mnt/boot/asahi 2>/dev/null || true
  red "Removing empty firmware dir so the config falls back to EFI extraction."
  rmdir "$HOST_DIR/firmware" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
bold "=== Step 8/9: local commit so the flake sees hw config + firmware ==="
# Flakes only see git-tracked files. Make a throwaway local commit in /tmp/nixos.
cd "$REPO"
git config user.email "install@local" 2>/dev/null || true
git config user.name  "asahi-install" 2>/dev/null || true
git add -A
git commit -m "install-time: hardware-configuration.nix + Asahi firmware for $HOST" || true

# ---------------------------------------------------------------------------
bold "=== Step 9/9: nixos-install --flake .#$HOST ==="
green "Using the Asahi binary cache; you'll be asked to set the root password at the end."
nixos-install --flake "$REPO#$HOST"

echo
green "==================================================================="
green " Install finished. Reboot with: reboot"
green " First boot: log in as root, create/set your user password."
green "==================================================================="
