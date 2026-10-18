#!/usr/bin/env nix-shell
#!nix-shell -i bash -p qemu socat imagemagick python3
# Boot a host's Limine menu (its real style, fake NixOS generations) in QEMU at the panel
# resolution and screenshot it.
# Usage: preview-limine.sh [-g generations] [-t timeout] [-w capture-delay-s] [-r WxH] <host> [out.png]
set -euo pipefail

declare -A NATIVE=(
  [DreamingWorkGalaxyBook]=2880x1800
  [DreamingWorkDell]=3840x2400
  [DreamingBlade]=1920x1080
  [DreamingDesk]=2560x1440
)
gens=3 timeout=no wait=12 res=
while getopts g:t:w:r: opt; do
  case $opt in
    g) gens=$OPTARG ;;
    t) timeout=$OPTARG ;;
    w) wait=$OPTARG ;;
    r) res=$OPTARG ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
host=${1:?host name}
out=${2:-/tmp/limine-preview-$host.png}
res=${res:-${NATIVE[$host]:?no native resolution for $host, pass -r WxH}}

repo=$(cd "$(dirname "$0")/../.." && pwd)
cfg="$repo#nixosConfigurations.$host"
info=$(nix eval --json "$cfg.config" --apply 'c: {
  inherit (c.boot.loader.limine) style;
  aspect = c.dreaming.core.boot.aspect;
  distro = c.system.nixos.distroName;
  label = "${c.system.nixos.distroName} ${c.system.nixos.codeName} ${c.system.nixos.label} (Linux ${c.boot.kernelPackages.kernel.modDirVersion})";
  drvs = map (d: d + "^*") (builtins.attrNames (builtins.getContext (toString c.boot.loader.limine.style.wallpapers)));
}')
mapfile -t drvs < <(python3 -c 'import json, sys; print(*json.load(sys.stdin)["drvs"], sep="\n")' <<<"$info")
[ ${#drvs[@]} -eq 0 ] || nix build --no-link "${drvs[@]}"
limine=$(nix build --no-link --print-out-paths "$cfg.config.boot.loader.limine.package.out")
ovmf=$(nix build --no-link --print-out-paths "$cfg.pkgs.OVMF.fd")/FV

work=$(mktemp -d)
trap 'kill ${qemu:-} 2>/dev/null; rm -rf "$work"' EXIT
mkdir -p "$work/esp/EFI/BOOT" "$work/esp/limine/wallpapers"
cp "$limine/share/limine/BOOTX64.EFI" "$work/esp/EFI/BOOT/"
printf %s "$info" >"$work/info.json"
python3 - "$work/esp" "$work/info.json" "$gens" "$timeout" "$res" <<'PY'
import json, shutil, sys
from pathlib import Path

esp, gens, timeout, res = Path(sys.argv[1]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
info = json.loads(Path(sys.argv[2]).read_text())
style = info["style"]
OPTIONS = [
    ("wallpaper_style", ["wallpaperStyle"]),
    ("backdrop", ["backdrop"]),
    ("interface_resolution", ["interface", "resolution"]),
    ("interface_branding", ["interface", "branding"]),
    ("interface_branding_colour", ["interface", "brandingColor"]),
    ("interface_help_colour", ["interface", "helpColor"]),
    ("interface_help_colour_bright", ["interface", "helpColorBright"]),
    ("interface_help_hidden", ["interface", "helpHidden"]),
    ("term_font_scale", ["graphicalTerminal", "font", "scale"]),
    ("term_font_spacing", ["graphicalTerminal", "font", "spacing"]),
    ("term_palette", ["graphicalTerminal", "palette"]),
    ("term_palette_bright", ["graphicalTerminal", "brightPalette"]),
    ("term_foreground", ["graphicalTerminal", "foreground"]),
    ("term_background", ["graphicalTerminal", "background"]),
    ("term_foreground_bright", ["graphicalTerminal", "brightForeground"]),
    ("term_background_bright", ["graphicalTerminal", "brightBackground"]),
    ("term_margin", ["graphicalTerminal", "margin"]),
    ("term_margin_gradient", ["graphicalTerminal", "marginGradient"]),
]
style["interface"]["resolution"] = style["interface"]["resolution"] or res

conf = [f"timeout: {timeout}", "editor_enabled: no", "graphics: yes", "default_entry: 2"]
for wallpaper in style["wallpapers"]:
    shutil.copy(wallpaper, esp / "limine/wallpapers")
    conf.append(f"wallpaper: boot():/limine/wallpapers/{Path(wallpaper).name}")
for key, path in OPTIONS:
    value = style
    for p in path:
        value = value[p]
    if value is not None:
        conf.append(f"{key}: {('yes' if value else 'no') if isinstance(value, bool) else value}")
conf.append(f"/+{info['distro']} default profile")
for k in range(gens):
    conf += [
        f"//Generation {69 - k}",
        "protocol: linux",
        f"comment: {info['label']}, built on 2026-10-{18 - k % 18:02d} 04:15:47",
        "kernel_path: boot():/limine/kernels/bzImage",
    ]
(esp / "limine/limine.conf").write_text("\n".join(conf) + "\n")
print(f"aspect={info['aspect']} res={res} gens={gens} timeout={timeout}", file=sys.stderr)
PY

cp "$ovmf/OVMF_VARS.fd" "$work/vars.fd"
chmod u+w "$work/vars.fd"
qemu-system-x86_64 -machine q35 -accel kvm -accel tcg -m 512 -display none -no-reboot \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf/OVMF_CODE.fd" \
  -drive if=pflash,format=raw,file="$work/vars.fd" \
  -drive file=fat:rw:"$work/esp",format=raw,if=virtio \
  -device VGA,edid=on,xres="${res%x*}",yres="${res#*x}",vgamem_mb=64,refresh_rate=30000 -vga none \
  -monitor unix:"$work/mon.sock",server,nowait &
qemu=$!
sleep "$wait"
echo "screendump $work/shot.ppm" | socat - unix-connect:"$work/mon.sock" >/dev/null
sleep 1
magick "$work/shot.ppm" "$out"
echo "$out"
