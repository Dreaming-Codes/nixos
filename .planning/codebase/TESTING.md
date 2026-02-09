# Testing Patterns

**Analysis Date:** 2026-02-08

## Test Framework

**Runner:**
- **None** — This repository has no automated test suite.

**There is no test runner, test framework, assertion library, or test configuration file in this codebase.**

This is a NixOS system configuration repository. The "testing" approach is fundamentally different from application codebases:

## Validation Strategy

**Instead of unit/integration tests, this codebase relies on:**

1. **Nix evaluation** — `nixos-rebuild` fails at evaluation time if modules have type errors, missing attributes, or circular dependencies
2. **CI build checks** — Garnix CI (see GitHub workflows) builds the full system closure, catching build-time errors
3. **Manual testing** — `update-system switch` applies config to the running system, providing immediate feedback

## CI/CD Pipeline

**Platform:** GitHub Actions + Garnix

**Workflows:**

**`update-flake.yml`** (`.github/workflows/update-flake.yml`):
- Schedule: Every Friday at 00:00 UTC (cron)
- Manually triggerable via `workflow_dispatch`
- Updates `flake.lock` and creates a PR on `auto-update-flake` branch
- Uses `peter-evans/create-pull-request@v7` action

**`auto-merge-flake.yml`** (`.github/workflows/auto-merge-flake.yml`):
- Triggered on `check_suite` completion for `auto-update-flake` branch
- Verifies PR is from same repository owner (security check against forks)
- Auto-merges with squash if all checks pass
- Comments on PR and pings `@copilot` if checks fail

**Garnix CI** (external, not configured in-repo):
- Builds NixOS system configurations to verify they evaluate and build successfully
- Triggered on PRs and pushes
- Results feed into the auto-merge workflow

## Build Verification Commands

```bash
# Evaluate and build the current host configuration (switch immediately)
update-system            # Provided by shell.nix, runs `nh os switch`

# Build for next boot only (no live switch)
update-system-boot       # Provided by shell.nix, runs `nh os boot`

# Check if current system matches config repo state
system-current           # Compares git ls-files hash with stored hash

# Manual rebuild (without shell.nix helpers)
nixos-rebuild build --flake .#DreamingDesk --impure --accept-flake-config
nixos-rebuild build --flake .#DreamingBlade --impure --accept-flake-config
```

**Note:** All builds require `--impure` due to SOPS secrets and `--accept-flake-config` for binary cache configuration.

## Host Configurations to Validate

Two hosts must build successfully for the repo to be considered "passing":

| Host | Flake attribute | Host path |
|------|----------------|-----------|
| DreamingDesk | `.#DreamingDesk` | `hosts/dreamingdesk/` |
| DreamingBlade | `.#DreamingBlade` | `hosts/dreamingblade/` |

## Rust Package Testing

**`packages/ci-keyboard-leds/`:**
- No Rust tests exist in `src/main.rs`
- Build verification: `nix build .#ci-keyboard-leds` (via `pkgs.callPackage`)
- No `#[test]` modules, no test files
- The `doCheck` is not explicitly set (defaults to `true` but there are no tests to run)

**`rsworktree` (fetched crate in `modules/programs/packages.nix`):**
- Tests explicitly disabled: `doCheck = false;` (tests require git and network access)

## Shell Script Verification

**No automated testing for shell scripts.** Scripts in `scripts/` are:
- `dynamic-workspaces.sh` — Hyprland IPC listener
- `mictoggle.sh` — Microphone toggle
- `mixer.sh` — Audio mixer toggle
- `vibeCommit.sh` — AI-assisted git commit
- `vibeMerge.sh` — AI-assisted worktree merge
- `razerpower.sh` — Razer power mode control

These are validated only by manual use.

## Auto-Update Testing

**`modules/services/auto-update.nix`** implements a self-updating mechanism with built-in safety:
- Checks for uncommitted changes before pulling (aborts if dirty)
- Uses `--ff-only` to avoid merge conflicts
- Retry logic (3 attempts with 60s delay) for `nixos-rebuild`
- Desktop notifications for status updates
- Weekly idempotency: tracks last update week in `/var/lib/nixos-auto-update/last-update-week`

**`shell.nix` update helpers** provide interactive safety:
- `system-current` — Hash comparison to skip redundant rebuilds
- `update-system` — Stash/unstash workflow for dirty working trees
- Conflict resolution via `opencode` AI agent

## What Would Be Needed for Testing

If testing were to be added to this codebase, the recommended approach would be:

**NixOS VM Tests (nixosTest):**
```nix
# Example pattern (not currently used)
nixosTest {
  name = "networking";
  nodes.machine = { ... }: {
    imports = [ ../modules/core/networking.nix ];
  };
  testScript = ''
    machine.wait_for_unit("network-online.target")
    machine.succeed("ping -c 1 1.1.1.1")
  '';
}
```

**Nix Evaluation Tests:**
```bash
# Verify all hosts evaluate without error
nix eval .#nixosConfigurations.DreamingDesk.config.system.build.toplevel --no-build
nix eval .#nixosConfigurations.DreamingBlade.config.system.build.toplevel --no-build
```

**Rust Tests (for ci-keyboard-leds):**
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_github_remote_ssh() {
        assert_eq!(
            parse_github_remote("git@github.com:user/repo.git"),
            Some("user/repo".to_string())
        );
    }

    #[test]
    fn test_parse_github_remote_https() {
        assert_eq!(
            parse_github_remote("https://github.com/user/repo.git"),
            Some("user/repo".to_string())
        );
    }
}
```

## Coverage

**Requirements:** None enforced
**Current coverage:** No test coverage tooling exists

---

*Testing analysis: 2026-02-08*
