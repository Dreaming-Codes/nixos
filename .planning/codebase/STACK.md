# Technology Stack

**Analysis Date:** 2026-02-08

## Languages

**Primary:**
- Nix (Nix Expression Language) - All system/home configuration, package definitions, module definitions (~43 `.nix` files)

**Secondary:**
- Rust (Edition 2024) - Custom package `ci-keyboard-leds` (`packages/ci-keyboard-leds/src/main.rs`)
- Bash - Shell scripts for system management (`scripts/`, `shell.nix`)
- QML - Custom SDDM login theme (`modules/desktop/sddm/theme/`)

## Runtime

**Environment:**
- NixOS (nixos-unstable channel) on x86_64-linux
- Determinate Nix 3.15.2 (via `inputs.determinate`)
- CachyOS kernel (latest, via `inputs.nix-cachyos-kernel`)

**Package Manager:**
- Nix Flakes (primary; channels disabled via `nix.channel.enable = false`)
- Lockfile: `flake.lock` (present, 772 lines)

## Frameworks

**Core:**
- NixOS module system - Declarative system configuration
- Home Manager - Per-user declarative configuration (via `inputs.home-manager`)
- Nix Flakes - Reproducible dependency management and build system

**Desktop:**
- Hyprland - Wayland compositor/window manager (`modules/desktop/hyprland.nix`, `home/dreamingcodes.nix`)
- KDE Plasma 6 - Desktop environment (DE fallback, KDE apps integration) (`modules/desktop/hyprland.nix`)
- SDDM - Display manager with custom Breeze-based theme (`modules/desktop/sddm/`)

**Build/Dev (in dev shell):**
- nil - Nix LSP server
- nixd - Nix language server
- nixfmt - Nix formatter (dev shell)
- alejandra - Nix formatter (opencode integration, `opencode.json`)

## Key Dependencies

**Flake Inputs (Critical):**
- `nixpkgs` (nixos-unstable) - Core package set
- `home-manager` - User environment management
- `sops-nix` - Secrets management with Age encryption
- `determinate` - Enhanced Nix tooling (parallel eval, FlakeHub)
- `nix-cachyos-kernel` - Performance-tuned Linux kernel
- `nixos-facter-modules` - Hardware auto-detection via `facter.json`
- `vicinae` + `vicinae-extensions` - Launcher/productivity tool (Raycast-like)
- `opencode` - AI coding assistant
- `nix-alien` - Run unpatched binaries on NixOS
- `nix-index-database` - Prebuilt nix-index for comma integration
- `nur` - Nix User Repository (community packages)
- `dolphin-overlay` - Dolphin emulator overlay
- `razer-laptop-controller` - Razer laptop keyboard/fan control (no-DKMS)

**Rust Crate Dependencies (ci-keyboard-leds, `packages/ci-keyboard-leds/Cargo.toml`):**
- `tokio` 1 (full) - Async runtime
- `reqwest` 0.12 (json) - HTTP client for GitHub API
- `hyprland-rs` (git, tokio+listener) - Hyprland IPC bindings
- `bincode` =1.3.3 - Wire protocol for razer daemon (pinned for compatibility)
- `serde` 1 + `serde_json` 1 - Serialization
- `anyhow` 1 - Error handling

**System Packages (Selected Critical, `modules/programs/packages.nix`):**
- `rustup` - Rust toolchain management
- `bun` - JavaScript/TypeScript runtime
- `nodejs` - Node.js runtime
- `uv` - Python package manager
- `gcc`, `clang`, `clang-tools` - C/C++ toolchain
- `sccache` - Shared compilation cache
- `gh` - GitHub CLI
- `docker` (via `modules/services/docker.nix`)
- `flatpak` (via `modules/services/flatpak.nix`)
- `sops` - Secrets encryption tool

## Configuration

**Environment:**
- direnv + nix-direnv for per-project environments (`home/common.nix`)
- `.envrc` at repo root: `use nix` (loads `shell.nix`)
- SDK symlinks at `/etc/nixos/.sdks/` for IDE integration: `nodejs`, `jdk`, `jdk17` (`modules/programs/development.nix`)
- `EDITOR`/`VISUAL` = `hx` (Helix editor)
- `TERMINAL` = `wezterm`
- `NIXOS_OZONE_WL` = `1` (Electron Wayland support)
- `SOPS_AGE_KEY_FILE` = `/home/dreamingcodes/.nixos/secrets/identity.age`

**Key Config Files:**
- `flake.nix` - Flake definition, inputs, host configurations
- `flake.lock` - Pinned dependency versions
- `opencode.json` - OpenCode formatter config (alejandra for `.nix`)
- `shell.nix` - Dev shell with nil, nixd, nixfmt, update-system scripts

**Build:**
- `nh` (NixOS Helper) for improved rebuild UX (`modules/core/nix.nix`)
  - Flake path: `~/.nixos/`
  - Auto-cleanup: daily, keep 2 generations, keep since 3 days
- `nixos-rebuild boot/switch` via `update-system` / `update-system-boot` scripts (`shell.nix`)
- Nix settings: `auto-optimise-store`, `builders-use-substitutes`, `relaxed` sandbox, parallel eval (`eval-cores = 0`)

**Binary Caches (in order of priority):**
1. `install.determinate.systems` (priority 20)
2. `cache.garnix.io` (priority 30) — CI builds
3. `cache.nixos.org` (priority 40)
4. `nix-community.cachix.org` (priority 41)
5. `attic.xuyh0120.win/lantian` (priority 42)
6. `numtide.cachix.org` (priority 43)
7. `vicinae.cachix.org` (priority 44)

## Platform Requirements

**Development:**
- NixOS with flakes enabled
- Age key at `/home/dreamingcodes/.nixos/secrets/identity.age` for secrets decryption
- Git repository access (GitHub)
- Dev shell provides: nil, nixd, nixfmt, update-system scripts

**Production (Hosts):**
- **DreamingDesk** (`hosts/dreamingdesk/`): Desktop with Intel CPU, AMD GPU (RADV), NVIDIA GPU (VFIO passthrough), ROCm support, Sunshine remote streaming, SDDM custom theme
- **DreamingBlade** (`hosts/dreamingblade/`): Razer laptop with AMD CPU, NVIDIA+AMD GPUs (PRIME offload/sync/reverse specialisations), CachyOS kernel, power management, Razer laptop control daemon, Keychron Q6 Pro keyboard, nRF development tools

**Hardware Support:**
- Bluetooth, WiFi (Intel AX210 optimized), USB
- GPU: AMD (ROCm, RADV), NVIDIA (CUDA, proprietary/open drivers, PRIME)
- Audio: PipeWire with ALSA, PulseAudio compat, JACK
- Keyboards: Razer (via razer-laptop-control daemon), Keychron Q6 Pro (QMK, udev rules)

---

*Stack analysis: 2026-02-08*
