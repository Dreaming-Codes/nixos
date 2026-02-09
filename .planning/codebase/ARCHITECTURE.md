# Architecture

**Analysis Date:** 2026-02-08

## Pattern Overview

**Overall:** NixOS Flake-based multi-host system configuration with modular decomposition

**Key Characteristics:**
- Declarative infrastructure-as-code using Nix Flakes as the single entry point
- Multi-host configuration sharing a common base with per-host specializations
- Three-tier module system: core OS → host-specific → user-specific (home-manager)
- Custom `mkHost` factory function abstracts host creation boilerplate
- Secrets managed via sops-nix with age encryption

## Layers

**Flake Entry Point:**
- Purpose: Declares all inputs (dependencies), outputs (host configurations), and binary caches
- Location: `flake.nix`
- Contains: Input declarations (nixpkgs, home-manager, sops-nix, etc.), `nixosConfigurations` output for each host
- Depends on: `lib/mkHost.nix` for host construction
- Used by: `nixos-rebuild`, CI workflows, `nh` tool

**Host Factory (lib):**
- Purpose: Abstracts the common pattern of creating a NixOS system configuration
- Location: `lib/mkHost.nix`
- Contains: `mkHost` function that assembles common modules + host-specific config + facter hardware detection
- Depends on: All flake inputs (passed through), `hosts/common.nix`, host-specific `hosts/<name>/default.nix`
- Used by: `flake.nix` outputs

**Utility Library (lib):**
- Purpose: Shared helper functions used across modules
- Location: `lib/mimes.nix`
- Contains: MIME type lists and `bindMimes` function for XDG default application binding
- Depends on: Nothing
- Used by: `home/common.nix`, `home/dreamingcodes.nix`

**Common Host Configuration:**
- Purpose: System-level settings shared by ALL hosts (boot, networking, desktop, services, users)
- Location: `hosts/common.nix`
- Contains: Imports of all shared modules from `modules/`, timezone/locale, state version
- Depends on: Every module in `modules/core/`, `modules/hardware/`, `modules/desktop/`, `modules/services/`, `modules/programs/`, `modules/users/dreamingcodes.nix`
- Used by: `lib/mkHost.nix` (included in every host)

**Host-Specific Configuration:**
- Purpose: Hardware definitions, GPU drivers, filesystems, host-only services, per-host Hyprland monitor/workspace layout
- Location: `hosts/dreamingdesk/default.nix`, `hosts/dreamingblade/default.nix`
- Contains: Filesystem mounts, kernel modules, GPU config (NVIDIA/AMD), hardware-specific services, host-only user imports (e.g., riccardo on dreamingdesk only), Hyprland monitor/workspace bindings via `home-manager.users.dreamingcodes`
- Depends on: Host-specific `facter.json` for hardware detection, additional modules (college.nix for blade, sddm for desk)
- Used by: `lib/mkHost.nix`

**NixOS Modules (System-Level):**
- Purpose: Reusable system configuration fragments organized by domain
- Location: `modules/`
- Contains: Six categories — `core/` (boot, networking, nix, ram, security, sops), `desktop/` (hyprland, fonts, xdg, sddm), `hardware/` (audio, graphics, optimization), `programs/` (development, packages, steam, college, virtualization), `services/` (docker, printing, samba, flatpak, auto-update), `users/` (dreamingcodes, riccardo)
- Depends on: `pkgs`, flake `inputs` passed via `specialArgs`
- Used by: `hosts/common.nix`, host-specific configs

**Home Manager Configuration (User-Level):**
- Purpose: Per-user environment, dotfiles, shell config, user services, window manager keybindings
- Location: `home/common.nix`, `home/dreamingcodes.nix`
- Contains: Shell programs (fish, starship, fzf, zoxide, eza, bat, direnv), editor config (helix, clangd), terminal (wezterm, zellij), Hyprland keybindings/services (swww, hypridle, swaync, ashell), Vicinae launcher config, user systemd services
- Depends on: `lib/mimes.nix`, `config/` directory for dotfiles, `scripts/` for shell scripts, flake inputs (vicinae, nix-index-database)
- Used by: `modules/users/dreamingcodes.nix` (imports both common.nix and dreamingcodes.nix), `modules/users/riccardo.nix` (imports only common.nix)

**Configuration Files (Dotfiles):**
- Purpose: Static configuration files deployed to user home directories via home-manager `home.file`
- Location: `config/`
- Contains: Editor configs (helix, wezterm), shell configs (zellij, cargo), Hyprland lock screen/scripts, wallpapers, application configs (ashell, spotify-player), OVMF firmware for VM GPU passthrough, Wireshark BLE sniffer extcap
- Depends on: Nothing (pure data)
- Used by: `home/common.nix`, `home/dreamingcodes.nix` via `home.file` symlinks

**Custom Packages:**
- Purpose: Locally-built packages not available in nixpkgs
- Location: `packages/ci-keyboard-leds/`
- Contains: Rust application that monitors CI status (GitHub Actions) and displays on keyboard LEDs via Razer API
- Depends on: openssl, systemd (build inputs)
- Used by: `hosts/dreamingblade/default.nix` (calls `pkgs.callPackage`)

**Shell Scripts:**
- Purpose: Utility scripts wrapped into derivations and deployed as user packages or systemd services
- Location: `scripts/`
- Contains: `dynamic-workspaces.sh` (Hyprland IPC monitor listener), `mictoggle.sh`, `mixer.sh`, `razerpower.sh`, `vibeCommit.sh`, `vibeMerge.sh`
- Depends on: System binaries (hyprctl, socat, jq, pactl, playerctl)
- Used by: `home/dreamingcodes.nix` (wraps into `writeShellScriptBin`), `hosts/dreamingblade/default.nix` (systemd service)

## Data Flow

**System Build and Activation:**

1. User runs `nh os switch` or `update-system` (from `shell.nix`)
2. Nix evaluates `flake.nix` → calls `lib.mkHost` for the target hostname
3. `mkHost` assembles: common NixOS modules + `hosts/common.nix` + `hosts/<host>/default.nix` + `facter.json` hardware config + extra modules
4. NixOS builder generates system closure including home-manager activation
5. System switch applies the new generation, sops-nix decrypts secrets to `/run/secrets/`
6. Home-manager activates per-user configurations (dotfiles, services, MIME bindings)

**Automated Update Pipeline:**

1. GitHub Actions runs `update-flake.yml` weekly (Fridays) → creates PR with updated `flake.lock`
2. Garnix CI builds all `nixosConfigurations` to validate
3. `auto-merge-flake.yml` auto-merges if CI passes
4. On-device: `nixos-auto-update` systemd service runs on boot, pulls changes, runs `nixos-rebuild boot`
5. Alternatively: user runs `update-system` interactively (from `shell.nix` dev shell) which handles stash/merge conflicts with opencode AI assistance

**Secrets Flow:**

1. Secrets stored encrypted in `secrets/secrets.yaml` (sops-nix format)
2. `.sops.yaml` defines age key for encryption/decryption
3. Private key at `secrets/identity.age` (gitignored) decrypts at activation time
4. `modules/core/sops.nix` defines secret templates → materialized at `/run/secrets/`
5. Services reference secrets via `EnvironmentFile` or nix `!include` directive

**User Session Startup (Hyprland):**

1. SDDM display manager starts → user logs in
2. Hyprland session target activates → triggers user systemd services
3. Services started: swww (wallpaper), ashell (status bar), swaync (notifications), hypridle (idle management), wl-clip-persist (clipboard), Vicinae (launcher)
4. On DreamingBlade: additionally starts dynamic-workspaces (monitor hotplug), ci-keyboard-leds (CI status), razerdaemon (keyboard control)

**State Management:**
- No mutable application state managed by this configuration
- System state version pinned at `24.11` in both NixOS and home-manager
- Auto-update state tracked in `/var/lib/nixos-auto-update/last-update-week`
- Config hash cached in `/var/lib/nixos-config-hash` for `system-current` checks

## Key Abstractions

**mkHost Factory:**
- Purpose: Eliminates boilerplate for defining new host configurations
- Examples: `lib/mkHost.nix`
- Pattern: Takes `{hostname, hostPath, system?, extraModules?}`, merges common modules (facter, NUR, home-manager, determinate, sops) with host-specific config, injects `specialArgs` for flake inputs access

**User Module Pattern (commonGroups):**
- Purpose: Shares group membership definitions between admin and non-admin users
- Examples: `modules/users/dreamingcodes.nix` (defines option), `modules/users/riccardo.nix` (consumes via `config.users.commonGroups`)
- Pattern: Uses `lib.mkOption` to export `commonGroups` list, admin user adds `adminGroups` on top

**SDK Links:**
- Purpose: Creates stable paths to SDK derivations at `/etc/nixos/.sdks/<name>` for IDE integration
- Examples: `modules/programs/development.nix`
- Pattern: Custom NixOS option `custom.misc.sdks.links` generates `/etc` symlinks to Nix store paths

**Script Wrapping:**
- Purpose: Converts plain shell scripts into proper Nix packages available in `$PATH`
- Examples: `home/dreamingcodes.nix` (toggleMic, toggleMixer, vibeMerge, vibeCommit, razerPower)
- Pattern: `pkgs.writeShellScriptBin "name" (builtins.readFile ../scripts/script.sh)` — scripts live in `scripts/`, wrapped at evaluation time

**Boot Specialisations (DreamingBlade):**
- Purpose: Provides multiple NVIDIA GPU modes selectable at boot time
- Examples: `hosts/dreamingblade/default.nix`
- Pattern: `specialisation` attribute set generates boot menu entries: `performance-open` (sync mode, open driver), `reverse-open` (reverse sync), `no-gpu` (NVIDIA completely disabled)

## Entry Points

**Primary Entry Point:**
- Location: `flake.nix`
- Triggers: `nixos-rebuild switch/boot`, `nh os switch`, `nix build`, CI evaluation
- Responsibilities: Defines two host configurations (`DreamingDesk`, `DreamingBlade`), declares all external dependencies as flake inputs, configures binary caches

**Development Shell:**
- Location: `shell.nix` + `.envrc`
- Triggers: Entering the repository directory (via direnv), or `nix-shell`
- Responsibilities: Provides `update-system`, `update-system-boot`, `system-current` commands, plus Nix LSPs (nil, nixd) and formatter (nixfmt)

**Auto-Update Service:**
- Location: `modules/services/auto-update.nix`
- Triggers: System boot (via `multi-user.target`)
- Responsibilities: Weekly pull + `nixos-rebuild boot` from remote, with retry logic and desktop notifications

**CI Workflows:**
- Location: `.github/workflows/update-flake.yml`, `.github/workflows/auto-merge-flake.yml`
- Triggers: Weekly cron (Friday) for update, check_suite completion for auto-merge
- Responsibilities: Automated flake.lock updates with CI validation gate

## Error Handling

**Strategy:** Fail-safe with retry and user notification

**Patterns:**
- Auto-update service: 3 retries with 60s delay, desktop notifications on success/failure, skips if uncommitted changes detected
- `update-system` (interactive): Stashes uncommitted changes, offers opencode AI conflict resolution on merge failures, restores staged files after stash pop
- Dynamic workspaces: `2>/dev/null` on workspace move commands (workspace may not exist), `on-failure` restart with 5s delay
- Razerdaemon race condition: `Restart=on-failure` with `RestartSec=2` to handle greeter→session daemon handoff
- Sops-nix: `!include` directive for access-tokens gracefully handles missing decrypted files

## Cross-Cutting Concerns

**Logging:** Systemd journal for all services; `echo` statements in shell scripts captured by journal when run as services
**Validation:** Hardware auto-detection via `nixos-facter-modules` (generates `facter.json`); Garnix CI validates all host configs build successfully on every push
**Authentication:** KWallet PAM auto-unlock at login; GPG agent via kwalletcli pinentry; Bitwarden SSH agent socket; sops-nix age-based secret decryption
**Process Priority:** `ananicy-cpp` with CachyOS rules + custom rules in `modules/hardware/optimization.nix` manages CPU/IO scheduling for 30+ processes; systemd-oomd with per-slice memory pressure monitoring

---

*Architecture analysis: 2026-02-08*
