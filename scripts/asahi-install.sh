#!/usr/bin/env bash
# DreamingWork — Asahi/aarch64 NixOS install helper.
#
# Run this INSIDE the booted nixos-apple-silicon installer (as root), NOT on macOS.
# It is interactive and STOPS for confirmation before anything destructive.
#
# Usage on the target:
#   sudo su
#   nix-shell -p git   # if git isn't already present
#   git clone -b asahi-wip https://github.com/Dreaming-Codes/nixos /tmp/nixos
#   bash /tmp/nixos/scripts/asahi-install.sh
#
# What it does, in order:
#   1. Shows the current partition table and waits for you to confirm.
#   2. Creates a root partition filling the free space (sgdisk -n 0:0 -s).
#   3. Formats it ext4 (label: nixos)  [asks first].
#   4. Mounts root at /mnt and the Asahi EFI partition at /mnt/boot.
#   5. Connects WiFi via iwd (optional; skip if wired).
#   6. Runs nixos-generate-config to produce hardware-configuration.nix.
#   7. Copies that hardware-configuration.nix into the flake's host dir.
#   8. Prints the exact nixos-install command to run (does NOT auto-run it,
#      because the firmware/flake decisions are made together with a human).

set -euo pipefail

DISK="/dev/nvme0n1"
FLAKE_SRC="$(cd "$(dirname "$0")/.." && pwd)"   # repo root (…/nixos)
HOST="DreamingWork"
HOST_DIR="$FLAKE_SRC/hosts/dreamingwork"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

confirm() {
  # $1 = prompt. Returns 0 on yes.
  local ans
  read -r -p "$1 [type YES to proceed]: " ans
  [ "$ans" = "YES" ]
}

if [ "$(id -u)" -ne 0 ]; then
  red "Must run as root. Run 'sudo su' first."
  exit 1
fi

if [ ! -b "$DISK" ]; then
  red "$DISK not found. This script must run inside the Linux installer, not macOS."
  red "Available block devices:"
  lsblk 2>/dev/null || true
  exit 1
fi

bold "=== Step 1/8: current partition table on $DISK ==="
sgdisk "$DISK" -p || true
echo
red "DANGER: do NOT touch partition 1 (iBootSystemContainer) or the last"
red "(RecoveryOSContainer). We only ADD a root partition in the free space."
echo
if ! confirm "Create a new root partition filling free space on $DISK?"; then
  red "Aborted before any changes were made."
  exit 1
fi

bold "=== Step 2/8: creating root partition (sgdisk -n 0:0 -s) ==="
sgdisk "$DISK" -n 0:0 -s
sgdisk "$DISK" -p
echo

# Find the new ext4-target partition: type 8300, highest-numbered such.
# We detect it as the partition we just created (largest 8300 / Linux filesystem).
ROOT_PART="$(
  lsblk -rno NAME,PARTTYPENAME "$DISK" 2>/dev/null \
    | awk '/[Ll]inux/ {print "/dev/"$1}' \
    | tail -n1
)"
# Fallback: guess by appending the highest partition number.
if [ -z "${ROOT_PART:-}" ] || [ ! -b "$ROOT_PART" ]; then
  LASTNUM="$(sgdisk "$DISK" -p | awk '/^[[:space:]]*[0-9]+/{n=$1} END{print n}')"
  ROOT_PART="${DISK}p${LASTNUM}"
fi

bold "Detected new root partition: $ROOT_PART"
red "VERIFY this is the partition you just created (type 8300, second-to-last)."
if ! confirm "Format $ROOT_PART as ext4 (label nixos)? THIS ERASES IT."; then
  red "Aborted before formatting. Inspect with: sgdisk $DISK -p"
  exit 1
fi

bold "=== Step 3/8: formatting $ROOT_PART ext4 ==="
mkfs.ext4 -L nixos "$ROOT_PART"

bold "=== Step 4/8: mounting root + Asahi EFI partition ==="
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
EFI_PARTUUID="$(cat /proc/device-tree/chosen/asahi,efi-system-partition)"
mount "/dev/disk/by-partuuid/${EFI_PARTUUID}" /mnt/boot
green "Mounted:"
findmnt /mnt; findmnt /mnt/boot

bold "=== Step 5/8: WiFi (iwd) ==="
if confirm "Connect WiFi now via iwctl? (say NO if using ethernet)"; then
  read -r -p "SSID: " SSID
  iwctl station wlan0 scan || true
  sleep 2
  iwctl station wlan0 connect "$SSID"
  sleep 2
  iwctl station wlan0 show || true
fi
green "Syncing time…"
systemctl restart systemd-timesyncd || true

bold "=== Step 6/8: nixos-generate-config ==="
nixos-generate-config --root /mnt
green "Generated /mnt/etc/nixos/hardware-configuration.nix:"
cat /mnt/etc/nixos/hardware-configuration.nix

bold "=== Step 7/8: copy hardware-configuration.nix into the flake ==="
cp /mnt/etc/nixos/hardware-configuration.nix "$HOST_DIR/hardware-configuration.nix"
green "Copied to $HOST_DIR/hardware-configuration.nix"
echo
red "NOTE: also save the Asahi peripheral firmware so the flake build is pure:"
echo "  mkdir -p $HOST_DIR/firmware"
echo "  cp /mnt/boot/asahi/{all_firmware.tar.gz,kernelcache*} $HOST_DIR/firmware/ 2>/dev/null || true"
echo "Then set in hosts/dreamingwork/default.nix:"
echo "    hardware.asahi.peripheralFirmwareDirectory = ./firmware;"
echo "(We'll do this edit together — do not run nixos-install until it's handled.)"

bold "=== Step 8/8: install command (run manually after firmware is handled) ==="
green "nixos-install --flake \"$FLAKE_SRC#$HOST\""
echo
bold "STOP HERE. Report back so we wire the firmware path + commit the hardware config."
