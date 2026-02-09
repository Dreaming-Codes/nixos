# Codebase Concerns

**Analysis Date:** 2026-02-08

## Tech Debt

**Samba share uses placeholder user/group:**
- Issue: The `public` Samba share has `"force user" = "username"` and `"force group" = "groupname"` — generic placeholders that were never configured to real values.
- Files: `modules/services/samba.nix` (lines 24–25)
- Impact: The public Samba share likely doesn't work correctly, or files are owned by a nonexistent user. Could cause permission errors or security issues.
- Fix approach: Set `force user` and `force group` to actual system users/groups (e.g., `"dreamingcodes"` and `"users"`), or use a dedicated share user. The share path `/mnt/Shares/Public` may also not exist on either host.

**Virtualization module commented out for DreamingDesk:**
- Issue: `flake.nix` has `# ./modules/programs/virtualization  # Enable when ready` commented out for the DreamingDesk host. The virtualization module tree (`modules/programs/virtualization/`) exists and is well-structured but is only usable if explicitly imported.
- Files: `flake.nix` (line 82), `modules/programs/virtualization/default.nix`, `modules/programs/virtualization/edk2.nix` (also has `./edk2.nix` commented out in its default.nix line 7)
- Impact: Virtualization features (VFIO passthrough, Looking Glass, spoofed QEMU/EDK2) are not available on DreamingDesk even though the code is maintained. Dead code until enabled.
- Fix approach: Either enable the module when ready, or move the virtualization directory to a separate branch/flake to reduce maintenance burden.

**QEMU patched overlay is fully commented out:**
- Issue: The patched-qemu overlay in `modules/programs/virtualization/qemu/pkg.nix` has all patched QEMU references commented out. The overlay file (`overlay.nix`) exists with full Hypervisor-Phantom patch logic but is unused.
- Files: `modules/programs/virtualization/qemu/pkg.nix` (lines 1–21), `modules/programs/virtualization/qemu/overlay.nix`
- Impact: The overlay.nix references files (`fake_battery.dsl`, `dmi_data.txt`) that don't exist in the repo (referenced at lines 20–21 of overlay.nix). The overlay uses `__noChroot = true` (sandbox escape) which would be a security concern if ever enabled.
- Fix approach: Either finish implementing the spoofed QEMU build (add missing files, test the overlay) or remove the dead code.

**Large nix-ld library list without documentation:**
- Issue: `modules/programs/development.nix` contains a 120-line list of `nix-ld.libraries` with no indication of which packages need which libraries. Adding or removing libraries is guesswork.
- Files: `modules/programs/development.nix` (lines 50–170)
- Impact: Bloated library set that's hard to maintain. May include unused libraries, and missing libraries won't be discovered until runtime failures.
- Fix approach: Add inline comments grouping libraries by the application(s) that need them.

**Wallpaper images tracked in git (~30MB of binary blobs):**
- Issue: 108 JPEG wallpaper files are committed directly into the git repository under `config/wallpaper/`. This bloats the repo history permanently.
- Files: `config/wallpaper/*.jpg` (108 files, ~30MB total)
- Impact: Every clone downloads 30MB+ of binary data. Git is not designed for binary assets; this slows clones and increases storage permanently (even if files are later deleted, blobs remain in history).
- Fix approach: Use Git LFS, a separate flake input, or a fetchurl-based approach to pull wallpapers at build time. Add `config/wallpaper/` to `.gitignore` after migration.

**ci-keyboard-leds build target not gitignored:**
- Issue: The `packages/ci-keyboard-leds/target/` directory (1.3GB of Rust build artifacts) is not in `.gitignore`. It's currently untracked, but `git add .` or similar broad commands could accidentally stage it.
- Files: `.gitignore`, `packages/ci-keyboard-leds/target/`
- Impact: Risk of accidentally committing 1.3GB of build artifacts. Even listing untracked files is slow with this directory present.
- Fix approach: Add `packages/ci-keyboard-leds/target/` to `.gitignore`.

**Hardcoded paths throughout the codebase:**
- Issue: Multiple files hardcode `/home/dreamingcodes` paths instead of using `config.users.users.dreamingcodes.home` or `$HOME`.
- Files:
  - `home/dreamingcodes.nix` (lines 34–36): hardcoded `"/home/dreamingcodes/.local/share/JetBrains/..."`, `"/home/dreamingcodes/.cargo/bin"`, `"/home/dreamingcodes/.bun/bin"`
  - `home/dreamingcodes.nix` (line 94): hardcoded `"/home/dreamingcodes/Documents/Obsidian Vault"`
  - `modules/core/sops.nix` (line 12): hardcoded `"/home/dreamingcodes/.nixos/secrets/identity.age"`
  - `modules/programs/packages.nix` (line 256): hardcoded `"/home/dreamingcodes/.nixos/secrets/identity.age"`
  - `hosts/dreamingdesk/default.nix` (lines 132–133): hardcoded ACL paths for `/home/riccardo`
- Impact: If the username or home directory ever changes, multiple files break. Non-portable and violates DRY.
- Fix approach: Use `config.home.homeDirectory` in home-manager context and `config.users.users.dreamingcodes.home` in NixOS context.

## Known Bugs

**KDE Connect indicator disabled due to bug:**
- Symptoms: KDE Connect indicator fails to start at time of writing (per inline comment).
- Files: `home/dreamingcodes.nix` (line 478)
- Trigger: Enabling `indicator = true` for kdeconnect service.
- Workaround: Indicator is disabled (`indicator = false`). KDE Connect still works, just without a system tray icon.

**Geoclue race condition with wpa_supplicant:**
- Symptoms: Geolocation service starts before WiFi is available, causing timezone detection failures.
- Files: `hosts/common.nix` (lines 48–50)
- Trigger: Fast boot where geoclue starts before WiFi scan completes.
- Workaround: systemd ordering dependency added (`After` and `Wants` on `wpa_supplicant.service`), but the comment says "reduce" not "fix" — the race may still occur.

**NUR documentation disabled as workaround:**
- Symptoms: NUR generates `builtins.toFile` warnings during NixOS documentation generation.
- Files: `hosts/common.nix` (lines 55–56)
- Trigger: Having NUR in the configuration with `documentation.nixos.enable = true`.
- Workaround: NixOS option documentation is completely disabled (`documentation.nixos.enable = false`), which means `man configuration.nix` doesn't work.

**Razerdaemon race condition on login:**
- Symptoms: The razer daemon started by the greeter session conflicts with the user session's daemon on login.
- Files: `hosts/dreamingblade/default.nix` (lines 141–146)
- Trigger: Logging in — greeter's daemon exits, user's daemon initially fails.
- Workaround: `Restart = "on-failure"` with `RestartSec = 2` retries until the socket is free. Functional but ugly — causes brief LED control gap on login.

## Security Considerations

**Relaxed Nix sandbox:**
- Risk: `nix.settings.sandbox = "relaxed"` in `modules/core/nix.nix` (line 53) allows builds to opt out of sandboxing. This was added for QEMU spoofing builds that need DMI access.
- Files: `modules/core/nix.nix` (line 53)
- Current mitigation: Only specific builds use `__noChroot`, and the QEMU overlay is currently commented out.
- Recommendations: Change to `sandbox = true` (strict) since the QEMU overlay that needed relaxed sandbox is disabled. If re-enabled, use a separate Nix daemon profile or `--option sandbox false` only for that specific build.

**Polkit grants all actions to wheel group:**
- Risk: The second polkit rule in `modules/core/security.nix` (lines 11–14) grants `polkit.Result.YES` to ALL actions for wheel users — this is an unrestricted polkit bypass.
- Files: `modules/core/security.nix` (lines 11–14)
- Current mitigation: Only trusted users (dreamingcodes) are in the wheel group, and `sudo-rs` is passwordless for wheel anyway.
- Recommendations: Remove the blanket rule and add specific rules only for actions that need it. The power profile rule (lines 3–9) shows the correct pattern.

**Passwordless sudo for wheel group:**
- Risk: `security.sudo-rs.wheelNeedsPassword = false` in `modules/core/security.nix` (line 19) means any process running as dreamingcodes can escalate to root without authentication.
- Files: `modules/core/security.nix` (line 19)
- Current mitigation: Single-user system with full-disk encryption (fscrypt enabled).
- Recommendations: Acceptable for a personal workstation, but be aware that any compromised user process can trivially escalate to root.

**Samba public share with guest access:**
- Risk: The Samba `public` share has `"guest ok" = "yes"` and uses placeholder user/group names, meaning anyone on the network can read/write files.
- Files: `modules/services/samba.nix` (lines 17–27)
- Current mitigation: Firewall is open for Samba, but only on the local network.
- Recommendations: Set proper `force user`/`force group`, consider disabling guest access, or restrict access by IP range.

**Age private key referenced by absolute path:**
- Risk: The sops age key is at `/home/dreamingcodes/.nixos/secrets/identity.age` and is referenced from multiple places. The `.gitignore` correctly excludes it, but the `SOPS_AGE_KEY_FILE` env var in `modules/programs/packages.nix` (line 256) exposes the path to all processes.
- Files: `modules/core/sops.nix` (line 12), `modules/programs/packages.nix` (line 256), `.gitignore`
- Current mitigation: File is gitignored; only exists on physical machines.
- Recommendations: Consider using a more restricted path (e.g., in `/run/secrets/`) and only exposing the env var to processes that need it.

**UDP port range 32768–60999 opened for Chromecast:**
- Risk: Very wide UDP port range opened in the firewall for Chromecast functionality.
- Files: `modules/core/networking.nix` (lines 92–96)
- Current mitigation: UDP only, ephemeral port range.
- Recommendations: Acceptable for a personal system, but this is essentially the entire ephemeral port range. Document why this specific range is needed.

## Performance Bottlenecks

**tmp-overflow-monitor runs every 10 seconds:**
- Problem: The timer for `tmp-overflow-monitor` fires every 10 seconds (`OnUnitActiveSec = "10s"`), launching a `find` + `fuser` scan of `/tmp/.ram`.
- Files: `modules/core/ram.nix` (lines 110–118)
- Cause: Extremely aggressive polling interval for a cleanup service. Each invocation spawns `find`, `fuser`, `du`, and potentially `mv` processes.
- Improvement path: Increase polling interval to 60–120 seconds. The mergerfs `moveonenospc` already handles the critical case (files actively being written). The monitor is "defense-in-depth" per the comment, so it doesn't need sub-minute resolution.

**ZRAM at 90% memory with swappiness 180:**
- Problem: `zramSwap.memoryPercent = 90` combined with `vm.swappiness = 180` means the system heavily favors swapping to compressed RAM. Under memory pressure, this can cause CPU spikes from compression overhead.
- Files: `modules/hardware/optimization.nix` (lines 175, 183)
- Cause: Aggressive ZRAM configuration tuned for maximum RAM utilization at the cost of CPU time.
- Improvement path: This is intentional for a developer workstation. Monitor with `zramctl` and `iostat` — if CPU compression overhead is noticeable, reduce `memoryPercent` to 50–75%.

## Fragile Areas

**Home Manager config for dreamingcodes (`home/dreamingcodes.nix`):**
- Files: `home/dreamingcodes.nix` (593 lines)
- Why fragile: This is the largest file in the codebase and mixes Hyprland keybindings, systemd services (6 services), application configs (vicinae, git, gpg, obs), and wallpaper/idle settings. Changes to any subsystem require editing this monolithic file.
- Safe modification: Test keybinding changes in isolation using `hyprctl keyword`. Test systemd services with `systemctl --user status`.
- Test coverage: None — no automated tests exist in this codebase.

**Dynamic workspace script (`scripts/dynamic-workspaces.sh`):**
- Files: `scripts/dynamic-workspaces.sh`, `hosts/dreamingblade/default.nix` (lines 90–108)
- Why fragile: Relies on specific monitor names (`DP-2`, `eDP-1`) and Hyprland IPC socket paths. If Hyprland changes its IPC protocol or monitor naming, the script silently breaks.
- Safe modification: Test monitor hotplug manually. Watch `journalctl --user -u dynamic-workspaces` for errors.
- Test coverage: None.

**Auto-update service (`modules/services/auto-update.nix`):**
- Files: `modules/services/auto-update.nix` (154 lines)
- Why fragile: The bash script handles git operations (fetch, pull, rebuild) as root on a user-owned repo. It assumes the repo remote is `origin` with branch `main` or `master`. The `--impure` flag and `--accept-flake-config` bypass safety checks.
- Safe modification: Test the script manually before deploying. The `git config --global --add safe.directory` call modifies root's global git config on every run.
- Test coverage: None.

**Shell update scripts (`shell.nix`):**
- Files: `shell.nix` (167 lines)
- Why fragile: The `update-system-common` script has complex stash/pull/conflict resolution logic with AI-assisted conflict resolution via `opencode run`. If `opencode` is unavailable or the model changes, the conflict resolution path fails.
- Safe modification: Always test with clean working tree first. The `STASHED` variable is used without initialization (shell default empty string behavior is relied upon).
- Test coverage: None.

## Scaling Limits

**GitHub API rate limiting for ci-keyboard-leds:**
- Current capacity: 5,000 requests/hour with authenticated token.
- Limit: At 30-second polling + window-switch triggers, heavy use could approach rate limits when frequently switching between repos.
- Scaling path: Add conditional polling (only poll when status is `Pending`), cache `Success`/`Failure` results longer, use GitHub webhooks instead of polling.

## Dependencies at Risk

**hyprland-rs pinned to git master branch:**
- Risk: `packages/ci-keyboard-leds/Cargo.toml` pins `hyprland` crate to `git = "...", branch = "master"` — no version pinning, builds may break unpredictably when upstream changes.
- Files: `packages/ci-keyboard-leds/Cargo.toml` (line 11)
- Impact: Any upstream breaking change to hyprland-rs API breaks the build. The `Cargo.lock` provides some protection but `nix build` may fetch latest.
- Migration plan: Pin to a specific git rev or wait for a crates.io release.

**nixpkgs-davinci pinned to specific commit:**
- Risk: `flake.nix` input `nixpkgs-davinci` is pinned to commit `d457818da697aa7711ff3599be23ab8850573a46` but appears unused in any module.
- Files: `flake.nix` (line 33)
- Impact: Unused input that gets fetched on every `flake update`. Dead weight.
- Migration plan: Verify it's unused and remove, or document where it's consumed.

## Missing Critical Features

**No automated testing or CI for NixOS configurations:**
- Problem: There are no `nix flake check` tests, no VM-based integration tests, and no linting (alejandra format checking) in CI. The GitHub workflows only handle flake.lock updates.
- Blocks: Breaking changes are only discovered at `nixos-rebuild` time on the actual machine.

**No Flake.lock pinning validation in CI:**
- Problem: The `update-flake.yml` workflow runs `nix flake update` and creates a PR, but doesn't run `nix build` or `nix flake check` to validate the updated lockfile works.
- Blocks: Updated dependencies could break the build, and the auto-merge workflow (`auto-merge-flake.yml`) would merge them if the (non-existent) check suite "succeeds" (vacuously true if there are no checks).

## Test Coverage Gaps

**No tests exist for any component:**
- What's not tested: The entire codebase — Nix modules, shell scripts, the Rust `ci-keyboard-leds` package, and the update/merge scripts have zero automated tests.
- Files: All files. No `*_test.nix`, `*.test.*`, `*.spec.*`, or test directories exist.
- Risk: Any change can break the system, and the only validation is manual `nixos-rebuild` on real hardware. The auto-update service could apply a broken configuration to the next boot.
- Priority: High — at minimum, add `nix flake check` with basic eval tests (ensure all hosts evaluate without errors) and `nix build` in CI.

---

*Concerns audit: 2026-02-08*
