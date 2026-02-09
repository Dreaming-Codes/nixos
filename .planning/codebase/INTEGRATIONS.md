# External Integrations

**Analysis Date:** 2026-02-08

## APIs & External Services

**GitHub API:**
- Used by: `ci-keyboard-leds` Rust daemon (`packages/ci-keyboard-leds/src/main.rs`)
- Endpoint: `https://api.github.com/repos/{owner}/{repo}/commits/{sha}/check-runs`
- Purpose: Poll CI/CD check run status for the current git repo and reflect status on keyboard LEDs
- SDK/Client: `reqwest` 0.12 (Rust HTTP client)
- Auth: `GITHUB_TOKEN` env var (Bearer token), sourced from sops secret via `/run/secrets/github_token_env`
- Also used by: Nix itself for private flake access (`access-tokens = github.com=<token>` via `modules/core/sops.nix`)

**Cloudflare Workers:**
- Used by: geoclue2 geolocation service (`hosts/common.nix`)
- Endpoint: `https://cloudflare-location-service.dreamingcodes.workers.dev/`
- Purpose: IP-based geolocation for automatic timezone, WiFi regulatory domain
- Auth: None (public endpoint)

**FlakeHub:**
- Used by: Nix flake inputs (`flake.nix`)
- Purpose: Fetch Determinate Systems flake inputs (determinate, nix-src)
- Endpoints: `https://flakehub.com/f/...`, `https://api.flakehub.com/f/pinned/...`
- Auth: None (public)

**Cachix / Binary Caches:**
- Used by: Nix build system (`flake.nix` nixConfig)
- Purpose: Download pre-built packages to avoid local compilation
- Endpoints: `cache.garnix.io`, `nix-community.cachix.org`, `numtide.cachix.org`, `vicinae.cachix.org`, `attic.xuyh0120.win/lantian`
- Auth: Public key verification (trusted-public-keys in `flake.nix`)

## Data Storage

**Databases:**
- None

**File Storage:**
- Local filesystem only
- Samba shares at `/mnt/Shares/Public` (`modules/services/samba.nix`)

**Caching:**
- Nix store (`/nix/store/`) with auto-optimise
- sccache for Rust compilation caching (installed via `modules/programs/packages.nix`)
- mergerfs `/tmp` with RAM (1GB tmpfs) + disk overflow (`modules/core/ram.nix`)

## Authentication & Identity

**System Auth:**
- PAM with KWallet integration (`modules/core/security.nix`, `modules/users/dreamingcodes.nix`)
- sudo-rs (Rust reimplementation of sudo), passwordless for wheel group (`modules/core/security.nix`)
- fscrypt for home folder encryption (`modules/core/security.nix`)

**Bitwarden SSH Agent:**
- Socket: `~/.bitwarden-ssh-agent.sock` (set via `SSH_AUTH_SOCK` in `home/common.nix`)
- Purpose: SSH key management via Bitwarden desktop app

**GPG:**
- Key: `1FE3A3F18110DDDD` (for git commit signing, `home/dreamingcodes.nix`)
- Agent: gpg-agent with KWallet pinentry (`home/dreamingcodes.nix`)
- Git credential helpers: `libsecret` + `git-credential-oauth` (`home/dreamingcodes.nix`)

**Secrets Management (sops-nix):**
- Implementation: `modules/core/sops.nix`
- Encryption: Age (identity key at `/home/dreamingcodes/.nixos/secrets/identity.age`)
- Secrets file: `secrets/secrets.yaml` (encrypted YAML)
- Decrypted secrets available at runtime under `/run/secrets/`:
  - `github_token` - GitHub personal access token
  - `telegram_bot_token` - Telegram bot API token
- Templates (rendered with secret interpolation):
  - `/run/secrets/nix-access-tokens.conf` - `access-tokens = github.com=<token>`
  - `/run/secrets/github_token_env` - `GITHUB_TOKEN=<token>` (env file for ci-keyboard-leds systemd service)

## Monitoring & Observability

**Error Tracking:**
- None (no external error tracking service)
- systemd coredump enabled (`modules/desktop/hyprland.nix`)

**Logs:**
- systemd journal (standard NixOS logging)
- ci-keyboard-leds: stderr debug output (`[DEBUG]` prefix, `packages/ci-keyboard-leds/src/main.rs`)

**Process Management:**
- ananicy-cpp with CachyOS rules (`modules/hardware/optimization.nix`) - automatic process priority/scheduling
- systemd-oomd for OOM management with 20s memory pressure threshold (`modules/hardware/optimization.nix`)
- bpftune for automatic kernel network tuning (`modules/hardware/optimization.nix`)

## CI/CD & Deployment

**Hosting:**
- GitHub (source repository)
- Local machines (deployment target - NixOS systems)

**CI Pipeline (GitHub Actions, `.github/workflows/`):**

1. **`update-flake.yml`** - Weekly flake.lock update
   - Schedule: Every Friday 00:00 UTC (`cron: '0 0 * * 5'`)
   - Uses: `DeterminateSystems/nix-installer-action`, `peter-evans/create-pull-request`
   - Action: Runs `nix flake update`, creates PR to `auto-update-flake` branch if changes detected
   - Manual trigger: `workflow_dispatch`

2. **`auto-merge-flake.yml`** - Auto-merge flake update PRs
   - Trigger: `check_suite` completed events on `auto-update-flake` branch
   - Action: If Garnix CI passes → squash merge + delete branch. If fails → comment on PR pinging owner + Copilot
   - Safety: Skips PRs from forks

**External CI (Garnix):**
- Builds NixOS configurations on push (referenced in auto-merge workflow)
- Binary cache: `cache.garnix.io`

**Auto-Update Service (`modules/services/auto-update.nix`):**
- Systemd service running on each boot
- Weekly schedule (tracks last update week in `/var/lib/nixos-auto-update/last-update-week`)
- Pulls latest git changes, runs `nixos-rebuild boot` with retry logic (3 attempts, 60s delay)
- Desktop notifications via `notify-send` to all logged-in users
- Conflicts with manual `nixos-upgrade.service`

**Manual Update Scripts (`shell.nix`):**
- `update-system` - Interactive: fetch, pull (with stash/conflict resolution via opencode), `nh os switch`
- `update-system-boot` - Same but `nh os boot` (apply on next reboot)
- `system-current` - Check if running system matches config hash
- Conflict resolution: Invokes `opencode run` with `github-copilot/gemini-3-flash-preview` model

## Networking & VPN

**DNS:**
- Cloudflare DNS over TLS (`1.1.1.1#cloudflare-dns.com`, `1.0.0.1#cloudflare-dns.com`) via systemd-resolved (`modules/core/networking.nix`)
- DHCP DNS ignored (custom nameservers enforced)

**VPN:**
- Mullvad VPN (`modules/programs/packages.nix`: `mullvad-vpn`, `mullvad-browser`)
- Cloudflare WARP (`modules/core/networking.nix`: `services.cloudflare-warp.enable = true`)

**WiFi:**
- NetworkManager with wpa_supplicant
- Enterprise WiFi (eduroam) optimizations: OKC, PMF, aggressive roaming (`modules/core/networking.nix`)
- Intel AX210 power save disabled for stability

**Local Network:**
- Samba file sharing with Avahi/mDNS discovery (`modules/services/samba.nix`)
- KDE Connect (ports 1714-1764, `modules/core/networking.nix`)
- Sunshine remote streaming (DreamingDesk only, `hosts/dreamingdesk/default.nix`)

## IPC & Local Sockets

**Razer Daemon Socket:**
- Path: `/tmp/razercontrol-socket`
- Protocol: bincode-serialized `DaemonCommand`/`DaemonResponse` enums over Unix socket
- Used by: `ci-keyboard-leds` to set keyboard LED colors (`packages/ci-keyboard-leds/src/main.rs`)

**ci-keyboard-leds CWD Socket:**
- Path: `$XDG_RUNTIME_DIR/ci-keyboard-leds.sock`
- Protocol: Newline-delimited directory paths over Unix socket
- Producer: Fish shell `__notify_ci_leds` function (`hosts/dreamingblade/default.nix`)
- Consumer: `ci-keyboard-leds` daemon, triggers GitHub API poll on CWD change

**Hyprland IPC:**
- Used by: `ci-keyboard-leds` via `hyprland-rs` async event listener
- Purpose: Detect active window changes to re-check CI status
- Used by: `dynamic-workspaces.sh` script via `socat` (`hosts/dreamingblade/default.nix`)

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- GitHub Actions webhooks (standard GitHub CI integration)

## Environment Configuration

**Required env vars (runtime):**
- `GITHUB_TOKEN` - GitHub API access (loaded from sops via systemd env file)
- `SOPS_AGE_KEY_FILE` - Path to Age identity key for sops decryption
- `SSH_AUTH_SOCK` - Bitwarden SSH agent socket path
- `HYPRLAND_INSTANCE_SIGNATURE` - Hyprland IPC (passed to ci-keyboard-leds service)
- `XDG_RUNTIME_DIR` - Standard XDG runtime directory

**Required env vars (build):**
- `PKG_CONFIG_PATH` - Points to OpenSSL dev headers (`modules/programs/packages.nix`)
- `SSL_CERT_FILE` / `NIX_SSL_CERT_FILE` - CA certificates for precompiled binaries (`modules/core/nix.nix`)

**Secrets location:**
- Encrypted: `secrets/secrets.yaml` (Age-encrypted YAML, committed to git)
- Identity key: `secrets/identity.age` (Age private key, committed - machine-specific)
- Decrypted at runtime: `/run/secrets/` (tmpfs, managed by sops-nix systemd activation)

---

*Integration audit: 2026-02-08*
