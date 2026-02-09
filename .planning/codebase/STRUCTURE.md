# Codebase Structure

**Analysis Date:** 2026-02-08

## Directory Layout

```
.nixos/
├── flake.nix               # Flake entry point: inputs, outputs, host definitions
├── flake.lock              # Pinned dependency versions
├── shell.nix               # Dev shell: update-system, LSPs, formatters
├── .envrc                  # direnv: auto-loads shell.nix on directory entry
├── .sops.yaml              # sops-nix: age key config for secret encryption
├── .gitignore              # Ignores .direnv, result, secrets/identity.age
├── opencode.json           # OpenCode AI tool configuration
├── RAMPLAN.md              # Active development planning document
│
├── lib/                    # Shared Nix library functions
│   ├── mkHost.nix          # Host factory: assembles NixOS configurations
│   └── mimes.nix           # MIME type lists and XDG binding helpers
│
├── hosts/                  # Per-host configurations (hardware + overrides)
│   ├── common.nix          # Shared host config: imports all common modules
│   ├── dreamingdesk/       # Desktop workstation
│   │   ├── default.nix     # AMD GPU, Intel CPU, multi-monitor, SDDM, riccardo user
│   │   └── facter.json     # Auto-detected hardware report
│   └── dreamingblade/      # Razer laptop
│       ├── default.nix     # NVIDIA+AMD hybrid, specialisations, keyboard LEDs
│       └── facter.json     # Auto-detected hardware report
│
├── modules/                # Reusable NixOS module fragments
│   ├── core/               # Essential system configuration
│   │   ├── boot.nix        # Limine bootloader, console font, quiet boot
│   │   ├── networking.nix  # NetworkManager, WiFi, DNS-over-TLS, firewall
│   │   ├── nix.nix         # Nix daemon settings, flake config, nh tool, GC
│   │   ├── ram.nix         # /tmp mergerfs (RAM + disk overflow), overflow monitor
│   │   ├── security.nix    # Polkit, sudo-rs, PAM, fscrypt, file limits
│   │   └── sops.nix        # Secrets management: GitHub token, templates
│   ├── desktop/            # Display and window management
│   │   ├── hyprland.nix    # Hyprland + Plasma6, SDDM, XKB, coredump, OVMF
│   │   ├── fonts.nix       # FiraCode Nerd Font
│   │   ├── xdg.nix         # XDG portals (Hyprland, KDE, GTK), MIME defaults
│   │   └── sddm/           # Custom SDDM theme
│   │       ├── default.nix # Theme derivation: patches Breeze with per-user session
│   │       └── theme/      # QML theme files
│   │           ├── Main.qml
│   │           ├── SessionButton.qml
│   │           └── metadata.desktop
│   ├── hardware/           # Hardware abstraction
│   │   ├── audio.nix       # PipeWire (ALSA, PulseAudio, JACK)
│   │   ├── graphics.nix    # GPU, Bluetooth, CPU microcode, firmware
│   │   └── optimization.nix # CachyOS kernel, ananicy-cpp, zram, swap, sysctl, OOM
│   ├── programs/           # Application-level configuration
│   │   ├── development.nix # SDK links, nix-ld libraries, partition-manager
│   │   ├── packages.nix    # System-wide packages (200+ packages), env vars
│   │   ├── steam.nix       # Steam + gamescope
│   │   ├── college.nix     # LC3 tools (host-specific import for blade)
│   │   └── virtualization/  # GPU passthrough VM setup (currently disabled)
│   │       ├── default.nix  # Aggregates virt sub-modules
│   │       ├── kernel.nix
│   │       ├── libvirt.nix
│   │       ├── edk2.nix
│   │       └── qemu/        # Custom QEMU with spoofing
│   │       └── looking_glass/ # Looking Glass client
│   └── services/           # System services
│       ├── docker.nix      # Docker + SPICE USB, oxker TUI
│       ├── printing.nix    # CUPS with HP plugin
│       ├── samba.nix       # Samba + Avahi mDNS
│       ├── flatpak.nix     # Flatpak + PackageKit, daily auto-update timers
│       └── auto-update.nix # Weekly nixos-rebuild boot on pull
│   └── users/              # User account definitions
│       ├── dreamingcodes.nix # Admin user: groups, PAM, home-manager imports
│       └── riccardo.nix    # Non-admin user: common groups, basic home-manager
│
├── home/                   # Home Manager configurations (user-level)
│   ├── common.nix          # Shared: fish, starship, fzf, eza, bat, direnv, zoxide, wezterm, helix, clangd config
│   └── dreamingcodes.nix   # User-specific: Hyprland binds, Vicinae, systemd services, GPG, git, OBS, zellij
│
├── config/                 # Static dotfiles and assets deployed via home.file
│   ├── ashell/             # Status bar config (config.toml)
│   ├── cargo/              # Rust cargo config (config.toml)
│   ├── extcap/             # Wireshark BLE sniffer plugin (Python)
│   │   └── SnifferAPI/     # nRF Sniffer API library
│   ├── helix/              # Helix editor: config.toml, languages.toml, theme, yazi-picker
│   │   └── themes/         # Custom transparent theme
│   ├── hypr/               # Hyprland assets: hyprlock.conf, lock screen images, scripts
│   │   ├── Fonts/          # JetBrains + SF Pro Display fonts for lock screen
│   │   └── Scripts/        # songdetail.sh for lock screen media info
│   ├── ovmf/               # UEFI firmware for VM GPU passthrough
│   ├── spotify-player/     # spotify-player config (app.toml)
│   ├── wallpaper/          # ~80 wallpaper images (JPG)
│   ├── wezterm/            # WezTerm terminal config (wezterm.lua)
│   └── zellij/             # Zellij terminal multiplexer config (config.kdl)
│
├── packages/               # Custom Nix packages (local derivations)
│   └── ci-keyboard-leds/   # Rust app: CI status → keyboard LEDs
│       ├── default.nix     # Nix build expression (rustPlatform.buildRustPackage)
│       ├── Cargo.toml      # Rust manifest
│       ├── Cargo.lock      # Rust dependency lock
│       └── src/main.rs     # Application source
│
├── scripts/                # Shell scripts (wrapped into packages by home-manager)
│   ├── dynamic-workspaces.sh  # Hyprland IPC: reconfigure workspaces on monitor hotplug
│   ├── mictoggle.sh        # Toggle microphone mute via pactl
│   ├── mixer.sh            # Toggle mixxc audio mixer overlay
│   ├── razerpower.sh       # Razer laptop power profile management
│   ├── vibeCommit.sh       # AI-assisted git commit via opencode
│   └── vibeMerge.sh        # Git worktree merge helper
│
├── secrets/                # Encrypted secrets (sops-nix)
│   ├── secrets.yaml        # Encrypted secret values (committed)
│   └── identity.age        # Age private key for decryption (GITIGNORED)
│
├── .github/workflows/      # CI/CD automation
│   ├── update-flake.yml    # Weekly flake.lock update → PR creation
│   └── auto-merge-flake.yml # Auto-merge flake update PR after CI passes
│
└── .planning/              # GSD planning documents
    └── codebase/           # Architecture analysis (this document)
```

## Directory Purposes

**`lib/`:**
- Purpose: Shared Nix functions used across the configuration
- Contains: Host factory function, MIME utility helpers
- Key files: `mkHost.nix` (core abstraction), `mimes.nix`

**`hosts/`:**
- Purpose: Machine-specific configuration — what makes each host unique
- Contains: Hardware definitions, filesystem mounts, GPU drivers, monitor layouts, host-only module imports, `facter.json` hardware reports
- Key files: `common.nix` (shared base), `dreamingdesk/default.nix`, `dreamingblade/default.nix`

**`modules/`:**
- Purpose: Reusable NixOS configuration fragments organized by domain
- Contains: 6 subdirectories (core, desktop, hardware, programs, services, users) with 20+ module files
- Key files: All `.nix` files in subdirectories — each is a self-contained configuration unit

**`home/`:**
- Purpose: Home Manager (user-level) configurations — shell, editor, services, keybindings
- Contains: Common config shared by all users, user-specific config for dreamingcodes
- Key files: `common.nix` (shell/editor/tools), `dreamingcodes.nix` (Hyprland/Vicinae/services)

**`config/`:**
- Purpose: Static configuration files and assets deployed to user home directories
- Contains: Editor configs, terminal configs, wallpapers, Hyprland assets, OVMF firmware, Wireshark plugins
- Key files: `helix/config.toml`, `wezterm/wezterm.lua`, `zellij/config.kdl`, `ashell/config.toml`

**`packages/`:**
- Purpose: Custom Nix derivations for software not in nixpkgs
- Contains: `ci-keyboard-leds` Rust application
- Key files: `ci-keyboard-leds/default.nix` (build expression), `ci-keyboard-leds/src/main.rs`

**`scripts/`:**
- Purpose: Shell scripts that get wrapped into Nix packages via `writeShellScriptBin`
- Contains: System automation scripts, Hyprland helpers, audio controls
- Key files: `dynamic-workspaces.sh`, `mictoggle.sh`, `mixer.sh`

**`secrets/`:**
- Purpose: Encrypted secrets managed by sops-nix
- Contains: `secrets.yaml` (encrypted, committed), `identity.age` (private key, gitignored)
- Key files: `secrets.yaml` (edit with `sops secrets/secrets.yaml`)

## Key File Locations

**Entry Points:**
- `flake.nix`: Primary configuration entry point — defines all hosts and inputs
- `shell.nix`: Development environment with update/check tools
- `.envrc`: Auto-activates dev shell via direnv

**Configuration:**
- `flake.lock`: Pinned versions of all flake inputs
- `.sops.yaml`: sops-nix encryption rules (which key encrypts which files)
- `opencode.json`: OpenCode AI tool configuration

**Core Logic:**
- `lib/mkHost.nix`: Host factory function — the central architectural abstraction
- `hosts/common.nix`: Module import manifest — defines what's shared across all hosts
- `modules/core/nix.nix`: Nix daemon configuration, garbage collection, registry pinning
- `modules/hardware/optimization.nix`: Performance tuning (kernel, scheduler, memory, OOM)

**User Configuration:**
- `home/common.nix`: Shared user environment (shell, editor, tools, dotfile links)
- `home/dreamingcodes.nix`: Primary user's Hyprland config, services, packages

**Testing:**
- No test framework — validation is done via Garnix CI building all `nixosConfigurations`

## Naming Conventions

**Files:**
- Module files: `lowercase-kebab.nix` or `lowercase.nix` (e.g., `auto-update.nix`, `boot.nix`)
- Directory-as-module: `<name>/default.nix` (e.g., `sddm/default.nix`, `qemu/default.nix`)
- User modules: `<username>.nix` (e.g., `dreamingcodes.nix`, `riccardo.nix`)
- Host directories: lowercase hostname without prefix (e.g., `dreamingblade/`, `dreamingdesk/`)
- Shell scripts: `camelCase.sh` (e.g., `vibeCommit.sh`, `mictoggle.sh`) or `kebab-case.sh` (e.g., `dynamic-workspaces.sh`)

**Directories:**
- Module categories: lowercase singular domain nouns (`core/`, `desktop/`, `hardware/`, `programs/`, `services/`, `users/`)
- Config directories: match the application name (`helix/`, `wezterm/`, `zellij/`, `ashell/`)

**NixOS Hostnames:**
- PascalCase with "Dreaming" prefix: `DreamingDesk`, `DreamingBlade`
- Host directory paths use lowercase: `dreamingdesk/`, `dreamingblade/`

## Where to Add New Code

**New Host Machine:**
1. Create `hosts/<hostname>/default.nix` with hardware config, filesystem mounts, GPU settings
2. Generate `hosts/<hostname>/facter.json` with `nixos-facter`
3. Add `nixosConfigurations.<HostName>` entry in `flake.nix` using `lib.mkHost`
4. Add any host-specific module imports in the host's `default.nix`

**New System Module:**
1. Create `modules/<category>/<name>.nix` in the appropriate category directory
2. Add import to `hosts/common.nix` (if shared) or to specific host's `default.nix` (if host-specific)
3. Follow existing pattern: `{pkgs, ...}: { ... }` function header with NixOS option assignments

**New User:**
1. Create `modules/users/<username>.nix` following pattern from `modules/users/riccardo.nix`
2. Use `config.users.commonGroups` for group membership
3. Import `home/common.nix` in the home-manager block
4. Optionally create `home/<username>.nix` for user-specific settings
5. Import the user module from the host's `default.nix` where that user should exist

**New Script:**
1. Add shell script to `scripts/<name>.sh`
2. Wrap in `home/dreamingcodes.nix` (or appropriate home config) using: `pkgs.writeShellScriptBin "name" (builtins.readFile ../scripts/name.sh)`
3. Add to `home.packages` list
4. If it needs to run as a systemd service, define `systemd.user.services.<name>` in the home config

**New Custom Package:**
1. Create `packages/<name>/default.nix` with build expression
2. Reference from host config using `pkgs.callPackage ../../packages/<name> {}`
3. For Rust packages, use `rustPlatform.buildRustPackage` pattern from `packages/ci-keyboard-leds/default.nix`

**New Static Config File:**
1. Add file(s) to `config/<app-name>/`
2. Link in `home/common.nix` (shared) or `home/dreamingcodes.nix` (user-specific) using:
   ```nix
   home.file.".config/<app-name>" = {
     source = ../config/<app-name>;
     recursive = true;
   };
   ```

**New Secret:**
1. Add entry to `modules/core/sops.nix` under `sops.secrets`
2. Add the secret value: `sops secrets/secrets.yaml` (encrypts with age key)
3. If needed as env file, create a `sops.templates` entry
4. Reference in services via `EnvironmentFile = "/run/secrets/<name>"`

**New Flake Input:**
1. Add to `inputs` section in `flake.nix`
2. Add `inputs.nixpkgs.follows = "nixpkgs"` if the input uses nixpkgs
3. If the module needs access, add to `specialArgs` in `lib/mkHost.nix`
4. Run `nix flake update <input-name>` to populate `flake.lock`

## Special Directories

**`.direnv/`:**
- Purpose: Cached direnv/nix-shell environment
- Generated: Yes (by direnv)
- Committed: No (gitignored)

**`config/ovmf/`:**
- Purpose: UEFI firmware files for GPU passthrough VMs
- Generated: No (manually placed binary files)
- Committed: Yes

**`config/wallpaper/`:**
- Purpose: Desktop wallpaper images rotated by swww timer
- Generated: No (manually curated)
- Committed: Yes (~80 JPG files)

**`.rsworktree/`:**
- Purpose: Git worktree directory for parallel branch development (managed by rsworktree tool)
- Generated: Yes (by rsworktree)
- Committed: No (gitignored)

**`packages/ci-keyboard-leds/target/`:**
- Purpose: Rust build artifacts
- Generated: Yes (by cargo)
- Committed: No (via package-level `.gitignore`)

**`.planning/`:**
- Purpose: GSD planning and codebase analysis documents
- Generated: Yes (by GSD commands)
- Committed: Situational

---

*Structure analysis: 2026-02-08*
