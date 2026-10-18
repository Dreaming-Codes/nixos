#!/usr/bin/env bash
# Run the theme in a real plymouthd (X11 renderer, unprivileged bwrap root) through the
# initrd unlock flow and capture frames per state.
# Usage: preview.sh [out-dir] [theme-package]
# Needs an X display (DISPLAY). Writes PNGs, dbg.log, animation.txt and perf.txt to out-dir.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out=${1:-/tmp/neuralink-preview}
nixpkgs=$(nix eval --raw --impure --expr "(builtins.getFlake \"$repo\").inputs.nixpkgs.outPath")
theme=${2:-$(nix build --no-link --print-out-paths --impure \
  --expr "with import $nixpkgs {}; callPackage $here {}")}
plymouth=$(nix build --no-link --print-out-paths --impure --expr "(import $nixpkgs {}).plymouth")

rm -rf "$out"
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"/{etc,run,themes}

# X11 has no capslock state, so the preview copy reports capslock once the passphrase overflows.
cp -rL "$theme/share/plymouth/themes/neuralink" "$work/themes/"
chmod -R u+w "$work/themes"
sed -i "s|Plymouth.GetCapslockState()|(ui.bullets > 20)|" "$work/themes/neuralink/neuralink.script"
sed -i "s|$theme/share/plymouth/themes|/run/plymouth/themes|" "$work/themes/neuralink/neuralink.plymouth"
printf '[Daemon]\nTheme=neuralink\nShowDelay=0\nDeviceTimeout=1\nDeviceScale=1\n' >"$work/etc/plymouthd.conf"
ln -s "$work/themes" "$work/run/themes"
ln -s "$plymouth/lib/plymouth" "$work/run/plugins"
ln -s "$plymouth/share/plymouth/plymouthd.defaults" "$work/run/plymouthd.defaults"

cat >"$work/inner.sh" <<'INNER'
set -u
P=$PLY
OUT=$OUTDIR
WAIT_MSG="Insert YubiKey, or press Enter for LUKS passphrase"
PIN="YubiKey PIN (Enter = LUKS passphrase)"
PASS="Please enter passphrase for disk cryptroot"

$P/bin/plymouthd --no-daemon --tty="$(tty)" --pid-file=/run/plymouth/pid \
  --debug-file="$OUT/dbg.log" --kernel-command-line="quiet splash" 2>"$OUT/stderr.log" &
PID=$!
sleep 1
$P/bin/plymouth show-splash
for _ in $(seq 50); do
  W=$(xwininfo -root -tree | awk '/"plymouthd"/ && !/ 10x10+/{print $1; exit}')
  [ -n "$W" ] && break
  sleep 0.1
done
[ -n "$W" ] || { echo "no plymouth window" >&2; kill $PID; exit 1; }

shot() { echo "shot $1 W=[$W]" >>"$OUT/shots.log"; import -window "$W" "$OUT/$1.png" 2>>"$OUT/shots.log"; }
keys() { xdotool type --window "$W" --delay 90 "$1"; }
enter() { xdotool key --window "$W" Return; }
ticks() { awk '{print $14 + $15}' /proc/$PID/stat; }
cpu() {
  local a b
  a=$(ticks); sleep "$2"; b=$(ticks)
  echo "$1 $(( (b - a) * 100 / $(getconf CLK_TCK) / ${2%.*} ))%" >>"$OUT/perf.txt"
}
ask() { $P/bin/plymouth ask-for-password --prompt="$1" >/dev/null & }

sleep 2.5
shot 01-boot
for i in 0 1 2 3 4 5; do shot "burst-$i"; done
cpu boot 3

$P/bin/plymouth display-message --text="$WAIT_MSG"
sleep 2.2
shot 02-awaiting
sleep 0.4
shot 02-awaiting-b
cpu awaiting 3

$P/bin/plymouth hide-message --text="$WAIT_MSG"
$P/bin/plymouth update --status=" "
sleep 0.3
shot 03-after-hide

ask "$PIN"
sleep 1.2
shot 04-pin-empty
keys 1234
sleep 0.5
shot 05-pin-bullets
cpu password 2
enter
sleep 0.6
shot 06-verifying
cpu verifying 2

ask "$PIN"
sleep 0.8
keys 98
sleep 0.4
shot 07-pin-retry
enter
sleep 0.5

ask "$PASS"
sleep 1.0
shot 08-passphrase-empty
keys "correct horse battery staple"
sleep 0.6
shot 09-passphrase-overflow
enter
sleep 1.2
shot 10-verifying

$P/bin/plymouth update-root-fs --new-root-dir=/
for i in 0 1 2 3 4 5 6 7; do sleep 0.15; shot "11-linked-$i"; done
cpu linked 2
sleep 2
shot 12-after-linked

$P/bin/plymouth quit
wait $PID
INNER

nix-shell -p bubblewrap util-linux xorg.xwininfo imagemagick xdotool --run "
  PLY=$plymouth OUTDIR=$out script -qec 'bwrap --dev-bind / / \
    --bind $work/etc /etc/plymouth --bind $work/run /run/plymouth \
    --unshare-user --uid 0 --gid 0 bash $work/inner.sh' /dev/null
  for i in 0 1 2 3 4; do
    printf 'burst-%s -> burst-%s: ' \$i \$((i + 1))
    compare -metric AE $out/burst-\$i.png $out/burst-\$((i + 1)).png null: 2>&1 || true
    echo
  done >$out/animation.txt
"

grep -hE 'Parser error|Execution error' "$out/dbg.log" "$out/stderr.log" >"$out/script-errors.txt" || true
echo "frames: $out"
echo "theme size: $(du -sh "$theme/share/plymouth/themes/neuralink" | cut -f1)"
echo "script errors: $(wc -l <"$out/script-errors.txt")"
cat "$out/animation.txt" "$out/perf.txt"
