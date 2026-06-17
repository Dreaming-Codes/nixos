# x86 app emulation on Asahi (deferred)

The `DreamingWork` host runs Asahi Linux on aarch64. Several apps used on the x86
hosts have **no native aarch64-linux build** in nixpkgs, so they're excluded from
`DreamingWork` for now (gated behind `pkgs.stdenv.hostPlatform.isx86_64` in
`modules/programs/packages.nix`).

This file tracks them and the plan to run them later via x86 emulation.

## Apps dropped on the work laptop

Verified x86_64-only (`nix eval ...meta.platforms`):

| App | Stopgap until emulation |
| --- | --- |
| `slack` | Web app (app.slack.com) |
| `zoom-us` | Web client / PWA |
| `discord` | Web app or `vesktop` (check aarch64) |
| `spotify` (desktop) | `psst` / `spotify-player` / `ncspot` are kept (native aarch64) + dankSpotify plugin |
| `onlyoffice-desktopeditors` | Web/PWA, or LibreOffice (native aarch64) |
| `mullvad-browser` | `helium-nightly` / `brave` / `tor-browser`-web |
| `tor-browser` | — |
| `saleae-logic-2` | — (proprietary; emulation only) |

Native aarch64 apps that ARE kept: `telegram-desktop`, `signalDesktop`,
`bitwarden-desktop`, `helium-nightly`, `brave`, `obs-studio`,
`frida-tools`, `jetbrains-toolbox`, `weylus`, plus all CLI/dev tooling.

The default browser is plain `brave` (binary `brave`, desktop file
`brave-browser.desktop`) on all hosts; `brave-origin-nightly` was dropped.

Note: `discord` is x86-only and excluded here, but the `$mod+D` launcher keybind
(Hyprland and niri `dms/binds.kdl`) is left in place — it's an inert keybind on
aarch64 until discord is available via emulation.

## Why this is hard on Asahi

- Asahi runs a **16K page-size** kernel; x86 binaries and FEX expect **4K pages**.
- Bare FEX therefore won't work directly. The Fedora Asahi method runs FEX inside a
  `libkrun` **4K-page microVM** via `muvm`, with `sommelier` bridging Wayland and a
  DRM native context for GPU acceleration.
- nixpkgs ships the pieces: `pkgs.fex`, `pkgs.muvm`, `pkgs.libkrun`, `sommelier`.
  `muvm`'s nixpkgs wrapper auto-adds `fex` on aarch64 and ships a NixOS-aware
  `muvm-init` (symlinks `/run/current-system` and `/run/opengl-driver` into the guest).
- There is **no maintained NixOS module** yet — tracked upstream in
  [nixos-apple-silicon#237](https://github.com/nix-community/nixos-apple-silicon/issues/237).
  The remaining glue (FEX rootfs/erofs, sommelier install, launcher wrappers, kvm
  access) is hand-rolled.

## Important constraint

Emulation is **runtime-only**. Nix still won't *evaluate* x86-only derivations on an
aarch64 host. To run the apps above under FEX you must obtain their x86 binaries from a
separate package set, e.g.:

```nix
let
  pkgsX86 = import inputs.nixpkgs {system = "x86_64-linux";};
in
  pkgsX86.slack # built/substituted as x86_64, launched via muvm+FEX
```

So enabling these later means: (1) keep the eval-time gating in place, and (2) add a
`pkgsX86` set + muvm/FEX launcher wrappers — not just flipping a flag.

## References

- Asahi project: https://asahilinux.org/
- Feature support: https://github.com/AsahiLinux/docs/wiki/Feature-Support
- nixos-apple-silicon: https://github.com/nix-community/nixos-apple-silicon
- UEFI standalone install guide: https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md
- muvm: https://github.com/AsahiLinux/muvm
- FEX-Emu: https://fex-emu.com/
- Emulation module tracking issue: https://github.com/nix-community/nixos-apple-silicon/issues/237
