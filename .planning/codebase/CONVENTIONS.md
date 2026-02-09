# Coding Conventions

**Analysis Date:** 2026-02-08

## Language Overview

This is a **NixOS configuration repository** with three languages:
- **Nix** (primary) — System and home-manager configuration
- **Bash** (secondary) — Helper scripts in `scripts/` and inline `writeShellScript` blocks
- **Rust** (secondary) — One custom package in `packages/ci-keyboard-leds/`

## Naming Patterns

**Nix Files:**
- Use `kebab-case` for filenames: `auto-update.nix`, `looking_glass/` (exception: uses `snake_case` for multi-word dirs)
- Module directories use `kebab-case` or `snake_case` inconsistently — prefer `kebab-case` for new modules
- Entry points for module directories: `default.nix`

**Nix Variables:**
- Use `camelCase` for local `let` bindings: `rsworktree`, `secureBootOVMF`, `nixos-auto-update`, `ci-keyboard-leds`
- Use `camelCase` for function parameters in `let` blocks
- Nix option paths use `kebab-case` with dots: `custom.misc.sdks`, `services.displayManager.sddm`

**Shell Scripts:**
- Use `camelCase` for script names when wrapped with `writeShellScriptBin`: `toggleMic`, `toggleMixer`, `razerPower`
- Use `kebab-case` for standalone script files: `dynamic-workspaces.sh`, `vibeMerge.sh` (mixed — some use `camelCase`)
- Use `UPPER_SNAKE_CASE` for shell variables: `NOTIFY_ID`, `PROC_NAME`, `WALLPAPER_DIR`, `CONFIG_DIR`

**Rust:**
- Use `snake_case` for functions and variables (standard Rust)
- Use `PascalCase` for types and enums: `CiStatus`, `DaemonCommand`, `RepoInfo`
- Use `UPPER_SNAKE_CASE` for constants: `POLL_INTERVAL_SECS`, `RAZER_SOCKET_PATH`

**Hosts:**
- Host directory names use `lowercase`: `dreamingdesk/`, `dreamingblade/`
- Host identifiers use `PascalCase`: `DreamingDesk`, `DreamingBlade` (in `flake.nix`)

## Nix Code Style

**Formatter:**
- `alejandra` — configured in `opencode.json` at project root
- Run via: `alejandra $FILE` (configured as opencode formatter for `.nix` files)
- The `shell.nix` dev environment also provides `nixfmt` but `alejandra` is the primary formatter

**Linting:**
- No explicit linter configured
- LSP via `nil` (Nix Language Server) and `nixd` provided in `shell.nix`

**Function Parameter Style:**
Use destructured attrsets with ellipsis for module parameters:
```nix
# Standard module signature — destructure needed args, use ellipsis
{pkgs, ...}: {
  # module body
}

# When multiple args are needed
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  # module body
}
```
- Place `{` on same line as parameter start
- One parameter per line when 3+ parameters
- Always include `...` (ellipsis) to accept extra args
- End parameter block with `}: {` or `}: let` on the closing line

**Let Bindings:**
Use `let ... in` for local definitions before the module body:
```nix
{pkgs, ...}: let
  myTool = pkgs.writeShellScriptBin "my-tool" ''
    # script content
  '';
in {
  # module body using myTool
}
```

**With Expressions:**
Use `with pkgs;` for package lists to reduce repetition:
```nix
environment.systemPackages = with pkgs; [
  wget
  gcc
  openssl
];
```

**String Interpolation:**
Use `${...}` inside double-quoted strings and multi-line strings (`'' ... ''`):
```nix
"${pkgs.terminus_font}/share/consolefonts/ter-120n.psf.gz"
```

## Import Organization

**Order in module files:**
1. Imports from other modules (relative paths)
2. NixOS/home-manager option declarations (`options = { ... }`)
3. Config body (`config = { ... }` or top-level attrset)

**Import Path Style:**
- Use relative paths from the file location: `../../secrets/secrets.yaml`, `../modules/core/boot.nix`
- Reference directories (with `default.nix`) by directory path: `./qemu`, `./looking_glass`
- Never use absolute paths for imports

**Flake Input References:**
Access flake inputs via `specialArgs` or direct `inputs` parameter:
```nix
inputs.nix-alien.packages.${stdenv.hostPlatform.system}.nix-alien
inputs.opencode.packages.${stdenv.hostPlatform.system}.default
```

## Module Design

**Single-Concern Modules:**
Each `.nix` file in `modules/` addresses one concern:
- `modules/core/boot.nix` — Boot loader configuration only
- `modules/services/docker.nix` — Docker setup only
- `modules/hardware/audio.nix` — Audio (PipeWire) only

**Module Composition:**
- Common config shared across hosts goes in `hosts/common.nix` via imports
- Host-specific config goes in `hosts/<hostname>/default.nix`
- User-specific config goes in `modules/users/<username>.nix`
- Home-manager config lives in `home/<username>.nix` (user-specific) and `home/common.nix` (shared)

**Exports Pattern:**
Use `lib.mkOption` to export values for use across modules:
```nix
# In modules/users/dreamingcodes.nix
options.users.commonGroups = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = commonGroups;
  description = "Common groups shared by all users";
};
```

**Custom Options Pattern:**
Follow NixOS module system conventions with `options`/`config` split:
```nix
# In modules/programs/development.nix
options = {
  custom.misc.sdks = {
    enable = mkEnableOption "sdk links";
    links = mkOption {
      type = types.attrs;
      default = {};
      description = ''Links to generate'';
    };
  };
};
config = mkIf cfg.enable ( ... );
```

## Inline Scripts Pattern

**Preferred approach for shell scripts:**
1. For scripts used as systemd services or user commands, use `pkgs.writeShellScriptBin`:
```nix
myScript = pkgs.writeShellScriptBin "my-script" ''
  # script body
'';
```

2. For scripts loaded from external files, use `builtins.readFile`:
```nix
toggleMic = pkgs.writeShellScriptBin "toggleMic" (builtins.readFile ../scripts/mictoggle.sh);
```

3. For systemd service `ExecStart`, use `pkgs.writeShellScript` (without `Bin`):
```nix
ExecStart = toString (
  pkgs.writeShellScript "swww-random-wallpaper" ''
    # script body
  ''
);
```

## Error Handling

**Nix:**
- No explicit error handling — Nix evaluation fails loudly on type mismatches
- Use `lib.mkDefault` for values that hosts may override:
  ```nix
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  ```
- Use `lib.mkForce` to override inherited values:
  ```nix
  Unit.PartOf = lib.mkForce ["hyprland-session.target"];
  ```

**Shell Scripts:**
- Use `set -euo pipefail` for robust error handling in important scripts (see `shell.nix` update scripts, `auto-update.nix`)
- Simpler utility scripts (`mictoggle.sh`, `mixer.sh`) do not use strict mode
- Use `2>/dev/null` with `|| true` for commands that may legitimately fail:
  ```bash
  git config --global --add safe.directory "$CONFIG_DIR" 2>/dev/null || true
  ```

**Rust:**
- Use `anyhow::Result` for the main function return type
- Use `?` operator for propagation within functions
- Use `.ok()?` pattern for `Option`-returning chains:
  ```rust
  let remote = Command::new("git").args(["remote", "get-url", "origin"]).current_dir(dir).output().ok()?;
  ```
- Use `let-else` pattern for early returns:
  ```rust
  let Some(ref info) = current_info else {
      update_keyboards(Rgb::BLUE);
      continue;
  };
  ```

## Comments

**When to Comment:**
- Add comments explaining **why** a configuration exists, not what it does:
  ```nix
  # Intel AX210 WiFi optimizations - disable power saving for better stability
  # Ensure geoclue starts after wpa_supplicant to reduce WiFi scan race condition
  ```
- Use inline comments for non-obvious port ranges or magic numbers:
  ```nix
  { from = 1714; to = 1764; } # KDE Connect
  ```
- Add TODO comments for planned future work:
  ```nix
  # TODO: Add Keychron Q6 Pro support when custom QMK firmware is ready
  ```

**Comment Style:**
- Nix: Use `#` line comments (no block comments in Nix)
- Shell: Use `#` line comments
- Rust: Use `///` for doc comments on public items, `//` for inline

## Systemd Service Pattern

**User services tied to Hyprland session:**
```nix
systemd.user.services.<name> = {
  Unit = {
    Description = "<description>";
    PartOf = ["hyprland-session.target"];
    After = ["hyprland-session.target"];
  };
  Install = {
    WantedBy = ["hyprland-session.target"];
  };
  Service = {
    ExecStart = "<command>";
    Restart = "always";  # or "on-failure"
    Type = "simple";     # or "oneshot"
  };
};
```

**System services:**
```nix
systemd.services.<name> = {
  description = "<description>";
  after = ["multi-user.target"];
  wantedBy = ["multi-user.target"];
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "<command>";
  };
};
```

Note: User services use `Unit = { ... }` (attrset), system services use `serviceConfig = { ... }`.

## Home-Manager Config Files

**Pattern for linking config directories:**
```nix
home.file."./.config/<app>" = {
  source = ../config/<app>;
  recursive = true;
};
```
- Config source files live in `config/<app>/` at repo root
- Linked to `~/.config/<app>` via home-manager's `home.file`
- Always use `recursive = true` for directories

## Package Definition Pattern

**For custom Rust packages:**
```nix
# packages/<name>/default.nix
{lib, rustPlatform, pkg-config, openssl, ...}:
rustPlatform.buildRustPackage {
  pname = "<name>";
  version = "<version>";
  src = ./.;
  cargoHash = "sha256-...";
  nativeBuildInputs = [pkg-config];
  buildInputs = [openssl];
  meta = with lib; {
    description = "...";
    license = licenses.mit;
  };
}
```

**For fetching crate packages:**
```nix
# Inline in a module
pkgs.rustPlatform.buildRustPackage rec {
  pname = "<name>";
  version = "<version>";
  src = pkgs.fetchCrate { inherit pname version; hash = "sha256-..."; };
  cargoHash = "sha256-...";
  doCheck = false;  # When tests need network
};
```

## Host Specialisation Pattern

**For hardware variants (used in `hosts/dreamingblade/default.nix`):**
```nix
specialisation = {
  <variant-name>.configuration = {
    system.nixos.tags = ["<tag>"];
    hardware.nvidia = {
      # Override specific settings with lib.mkForce
    };
  };
};
```

## Lib Helper Pattern

**Shared utilities in `lib/`:**
- `lib/mkHost.nix` — Host builder function, returns `{ mkHost = ...; }`
- `lib/mimes.nix` — MIME type lists and helper functions, returns plain attrset
- Import in modules with: `mimes = import ../lib/mimes.nix;`

---

*Convention analysis: 2026-02-08*
