use anyhow::{bail, Context, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::Utc;
use clap::Parser;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Parser)]
#[command(
    name = "nix-file-overlay",
    about = "Temporarily override Nix-managed (symlinked) files"
)]
struct Cli {
    /// File path to overlay
    path: Option<PathBuf>,

    /// List all overlays
    #[arg(short = 'l', long)]
    list: bool,

    /// Remove an overlay (unmount, restoring the original symlink)
    #[arg(short = 'r', long, value_name = "PATH")]
    remove: Option<PathBuf>,

    /// Apply overlay back to NixOS/HM config source
    #[arg(short = 'a', long, value_name = "PATH")]
    apply: Option<PathBuf>,

    /// Re-apply overlays from registries (internal, used by systemd/activation)
    #[arg(long)]
    restore: bool,

    /// Specify registry file for --restore
    #[arg(long, value_name = "PATH")]
    registry: Option<PathBuf>,

    /// Persist overlay across reboots/rebuilds
    #[arg(short = 'p', long)]
    persistent: bool,

    /// Skip opening editor after overlay
    #[arg(long)]
    no_edit: bool,
}

#[derive(Serialize, Deserialize, Clone)]
struct OverlayEntry {
    stored_copy: PathBuf,
    original_target: Option<String>,
    persistent: bool,
    created_at: String,
    mapping_key: Option<String>,
    mapping_type: Option<String>,
}

type Registry = HashMap<String, OverlayEntry>;

#[derive(Deserialize)]
#[allow(dead_code)]
struct HmMappingEntry {
    target: Option<String>,
    source: Option<String>,
    recursive: Option<bool>,
    #[serde(rename = "repoRelative")]
    repo_relative: Option<String>,
    #[serde(rename = "type")]
    entry_type: Option<String>,
}

#[derive(Deserialize)]
#[allow(dead_code)]
struct EtcMappingEntry {
    path: Option<String>,
    source: Option<String>,
    #[serde(rename = "definedIn")]
    defined_in: Option<Vec<String>>,
    #[serde(rename = "userDefinedIn")]
    user_defined_in: Option<Vec<String>>,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.list {
        return cmd_list();
    }
    if let Some(path) = &cli.remove {
        return cmd_remove(path);
    }
    if let Some(path) = &cli.apply {
        return cmd_apply(path);
    }
    if cli.restore {
        return cmd_restore(cli.registry.as_deref());
    }
    if let Some(path) = &cli.path {
        return cmd_overlay(path, cli.persistent, cli.no_edit);
    }

    bail!("No command specified. Use --help for usage information.");
}

// ── Path helpers ─────────────────────────────────────────────────────

fn get_home_dir() -> Result<PathBuf> {
    dirs::home_dir().context("Could not determine home directory")
}

fn get_data_dir() -> Result<PathBuf> {
    let home = get_home_dir()?;
    Ok(home.join(".local/share/nix-file-overlay"))
}

fn get_system_data_dir() -> PathBuf {
    PathBuf::from("/var/lib/nix-file-overlay")
}

fn get_tmp_dir() -> Result<PathBuf> {
    let uid = unsafe { libc::getuid() };
    Ok(PathBuf::from(format!("/tmp/nix-file-overlay-{uid}")))
}

fn is_user_path(path: &Path) -> Result<bool> {
    let home = get_home_dir()?;
    Ok(path.starts_with(&home))
}

fn storage_dir_for(path: &Path, persistent: bool) -> Result<PathBuf> {
    if !persistent {
        return get_tmp_dir();
    }
    if is_user_path(path)? {
        get_data_dir()
    } else {
        Ok(get_system_data_dir())
    }
}

fn registry_path_for(path: &Path, persistent: bool) -> Result<PathBuf> {
    Ok(storage_dir_for(path, persistent)?.join("registry.json"))
}

fn encode_path(path: &Path) -> String {
    URL_SAFE_NO_PAD.encode(path.to_string_lossy().as_bytes())
}

fn resolve_path(path: &Path) -> Result<PathBuf> {
    let abs = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    if !abs.exists() && !abs.is_symlink() {
        bail!("Path does not exist: {}", abs.display());
    }
    Ok(abs)
}

fn get_symlink_target(path: &Path) -> Option<String> {
    fs::read_link(path)
        .ok()
        .map(|t| t.to_string_lossy().into_owned())
}

// ── Registry helpers ─────────────────────────────────────────────────

fn load_registry(path: &Path) -> Result<Registry> {
    if !path.exists() {
        return Ok(Registry::new());
    }
    let data = fs::read_to_string(path)
        .with_context(|| format!("Failed to read registry at {}", path.display()))?;
    serde_json::from_str(&data)
        .with_context(|| format!("Failed to parse registry at {}", path.display()))
}

fn save_registry(path: &Path, registry: &Registry) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create directory {}", parent.display()))?;
    }
    let data = serde_json::to_string_pretty(registry)?;
    fs::write(path, data)
        .with_context(|| format!("Failed to write registry at {}", path.display()))?;
    Ok(())
}

fn collect_registry_paths(path: &Path) -> Result<Vec<PathBuf>> {
    let mut paths = Vec::new();
    if let Ok(data_dir) = get_data_dir() {
        paths.push(data_dir.join("registry.json"));
    }
    paths.push(get_system_data_dir().join("registry.json"));
    if let Ok(tmp_dir) = get_tmp_dir() {
        paths.push(tmp_dir.join("registry.json"));
    }
    for persistent in [true, false] {
        if let Ok(p) = registry_path_for(path, persistent) {
            if !paths.contains(&p) {
                paths.push(p);
            }
        }
    }
    Ok(paths)
}

// ── Sudo wrappers ────────────────────────────────────────────────────

fn is_bind_mounted(path: &Path) -> Result<bool> {
    // When bind-mounting on a symlink, the kernel resolves it, so /proc/mounts
    // shows the resolved (canonical) path, not the symlink path. Check both.
    let canonical = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let path_str = path.to_string_lossy();
    let canon_str = canonical.to_string_lossy();

    let file = fs::File::open("/proc/mounts").context("Failed to read /proc/mounts")?;
    let reader = BufReader::new(file);
    for line in reader.lines() {
        let line = line?;
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && (parts[1] == path_str || parts[1] == canon_str) {
            return Ok(true);
        }
    }
    Ok(false)
}

fn run_sudo_mount(source: &Path, target: &Path) -> Result<()> {
    let status = Command::new("sudo")
        .args(["mount", "--bind"])
        .arg(source)
        .arg(target)
        .status()
        .context("Failed to execute sudo mount")?;
    if !status.success() {
        bail!(
            "sudo mount --bind {} {} failed with exit code {}",
            source.display(),
            target.display(),
            status.code().unwrap_or(-1)
        );
    }
    Ok(())
}

fn run_sudo_umount(target: &Path) -> Result<()> {
    let status = Command::new("sudo")
        .args(["umount"])
        .arg(target)
        .status()
        .context("Failed to execute sudo umount")?;
    if !status.success() {
        bail!(
            "sudo umount {} failed with exit code {}",
            target.display(),
            status.code().unwrap_or(-1)
        );
    }
    Ok(())
}

// ── Mapping helpers ──────────────────────────────────────────────────

fn get_hm_mapping_path() -> Result<PathBuf> {
    let username = std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_else(|_| "unknown".to_string());
    let etc_path = PathBuf::from(format!("/etc/nix-file-overlay/hm-mapping-{username}.json"));
    if etc_path.exists() {
        return Ok(etc_path);
    }
    let data_dir = get_data_dir()?;
    Ok(data_dir.join("hm-mapping.json"))
}

fn find_mapping_key_for_path(abs_path: &Path) -> Result<Option<(String, String)>> {
    let home = get_home_dir()?;

    if abs_path.starts_with(&home) {
        let hm_mapping_path = get_hm_mapping_path()?;
        if hm_mapping_path.exists() {
            let data = fs::read_to_string(&hm_mapping_path)?;
            let mapping: HashMap<String, HmMappingEntry> = serde_json::from_str(&data)?;

            let rel = abs_path.strip_prefix(&home).unwrap();
            let rel_str = format!("./{}", rel.display());
            let rel_str_no_dot = rel.to_string_lossy().to_string();

            for (key, entry) in &mapping {
                let target = entry.target.as_deref().unwrap_or(key);
                let target_clean = target.strip_prefix("./").unwrap_or(target);

                if target_clean == rel_str.strip_prefix("./").unwrap_or(&rel_str)
                    || target_clean == rel_str_no_dot
                {
                    return Ok(Some((key.clone(), "hm".to_string())));
                }

                if entry.recursive.unwrap_or(false) {
                    let target_path = Path::new(target_clean);
                    let rel_path = Path::new(rel_str.strip_prefix("./").unwrap_or(&rel_str));
                    if rel_path.starts_with(target_path) {
                        return Ok(Some((key.clone(), "hm".to_string())));
                    }
                }
            }
        }
    }

    let etc_mapping_path = Path::new("/etc/nix-file-overlay/etc-mapping.json");
    if etc_mapping_path.exists() && abs_path.starts_with("/etc/") {
        let data = fs::read_to_string(etc_mapping_path)?;
        let mapping: HashMap<String, EtcMappingEntry> = serde_json::from_str(&data)?;

        for (key, entry) in &mapping {
            if let Some(p) = &entry.path {
                if Path::new(p) == abs_path {
                    return Ok(Some((key.clone(), "etc".to_string())));
                }
            }
        }
    }

    Ok(None)
}

// ── Overlay command ──────────────────────────────────────────────────

fn cmd_overlay(path: &Path, persistent: bool, no_edit: bool) -> Result<()> {
    let abs_path = resolve_path(path)?;

    if !abs_path.is_symlink() {
        bail!(
            "Only Nix-managed files (symlinks) can be overlaid. \
             {} is not a symlink.",
            abs_path.display()
        );
    }

    if !abs_path.is_file() {
        bail!(
            "Symlink does not point to a regular file: {}",
            abs_path.display()
        );
    }

    if is_bind_mounted(&abs_path)? {
        bail!("Path is already overlaid: {}", abs_path.display());
    }

    let original_target = get_symlink_target(&abs_path);

    // Read content through the symlink
    let content = fs::read(&abs_path)
        .with_context(|| format!("Failed to read file: {}", abs_path.display()))?;

    let storage = storage_dir_for(&abs_path, persistent)?;
    let overlays_dir = storage.join("overlays");
    fs::create_dir_all(&overlays_dir)?;

    let encoded = encode_path(&abs_path);
    let stored_copy = overlays_dir.join(&encoded);
    fs::write(&stored_copy, &content)?;

    // Make the copy writable
    let mut perms = fs::metadata(&stored_copy)?.permissions();
    perms.set_mode(perms.mode() | 0o600);
    fs::set_permissions(&stored_copy, perms)?;

    let mapping_info = find_mapping_key_for_path(&abs_path)?;

    // Bind mount the editable copy on top of the symlink path
    run_sudo_mount(&stored_copy, &abs_path)?;

    let reg_path = registry_path_for(&abs_path, persistent)?;
    let mut registry = load_registry(&reg_path)?;
    registry.insert(
        abs_path.to_string_lossy().into_owned(),
        OverlayEntry {
            stored_copy: stored_copy.clone(),
            original_target,
            persistent,
            created_at: Utc::now().to_rfc3339(),
            mapping_key: mapping_info.as_ref().map(|(k, _)| k.clone()),
            mapping_type: mapping_info.map(|(_, t)| t),
        },
    );
    save_registry(&reg_path, &registry)?;

    eprintln!(
        "Overlaid {} ({})",
        abs_path.display(),
        if persistent {
            "persistent"
        } else {
            "temporary"
        },
    );

    if !no_edit {
        let editor = std::env::var("NIX_FILE_OVERLAY_EDITOR")
            .or_else(|_| std::env::var("EDITOR"))
            .unwrap_or_else(|_| "vi".to_string());
        let status = Command::new(&editor)
            .arg(&abs_path)
            .status()
            .with_context(|| format!("Failed to launch editor: {editor}"))?;
        if !status.success() {
            eprintln!("Editor exited with non-zero status");
        }
    }

    Ok(())
}

// ── List command ─────────────────────────────────────────────────────

fn cmd_list() -> Result<()> {
    let mut entries: Vec<(String, OverlayEntry, String)> = Vec::new();

    if let Ok(data_dir) = get_data_dir() {
        let reg_path = data_dir.join("registry.json");
        if let Ok(reg) = load_registry(&reg_path) {
            for (path, entry) in reg {
                entries.push((path, entry, "user".to_string()));
            }
        }
    }

    let sys_reg_path = get_system_data_dir().join("registry.json");
    if let Ok(reg) = load_registry(&sys_reg_path) {
        for (path, entry) in reg {
            entries.push((path, entry, "system".to_string()));
        }
    }

    if let Ok(tmp_dir) = get_tmp_dir() {
        let reg_path = tmp_dir.join("registry.json");
        if let Ok(reg) = load_registry(&reg_path) {
            for (path, entry) in reg {
                if !entries.iter().any(|(p, _, _)| p == &path) {
                    entries.push((path, entry, "temp".to_string()));
                }
            }
        }
    }

    if entries.is_empty() {
        eprintln!("No active overlays.");
        return Ok(());
    }

    println!(
        "{:<60} {:<10} {:<12} {}",
        "PATH", "STATUS", "PERSISTENCE", "CREATED"
    );
    println!("{}", "-".repeat(100));

    for (path, entry, scope) in &entries {
        let mounted = is_bind_mounted(Path::new(path)).unwrap_or(false);
        let status = if mounted { "active" } else { "stale" };
        let persistence = if entry.persistent {
            format!("persistent/{scope}")
        } else {
            "temporary".to_string()
        };
        println!(
            "{:<60} {:<10} {:<12} {}",
            path, status, persistence, entry.created_at
        );
    }

    Ok(())
}

// ── Remove command ───────────────────────────────────────────────────

fn cmd_remove(path: &Path) -> Result<()> {
    let abs_path = resolve_path(path).unwrap_or_else(|_| {
        if path.is_absolute() {
            path.to_path_buf()
        } else {
            std::env::current_dir().unwrap_or_default().join(path)
        }
    });
    let path_str = abs_path.to_string_lossy().into_owned();

    let registries = collect_registry_paths(&abs_path)?;

    let mut found = false;
    for reg_path in &registries {
        let mut registry = match load_registry(reg_path) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if let Some(entry) = registry.remove(&path_str) {
            found = true;

            // Unmount to reveal the original symlink underneath
            if is_bind_mounted(&abs_path).unwrap_or(false) {
                run_sudo_umount(&abs_path)?;
            }

            if entry.stored_copy.exists() {
                fs::remove_file(&entry.stored_copy).ok();
            }

            save_registry(reg_path, &registry)?;
            eprintln!("Removed overlay for {}", abs_path.display());
        }
    }

    if !found {
        bail!("No overlay found for {}", abs_path.display());
    }

    Ok(())
}

// ── Apply command ────────────────────────────────────────────────────

fn cmd_apply(path: &Path) -> Result<()> {
    let abs_path = resolve_path(path)?;
    let path_str = abs_path.to_string_lossy().into_owned();

    let registries = collect_registry_paths(&abs_path)?;
    let mut found_entry: Option<(OverlayEntry, PathBuf)> = None;

    for reg_path in &registries {
        let registry = match load_registry(reg_path) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if let Some(entry) = registry.get(&path_str) {
            found_entry = Some((entry.clone(), reg_path.clone()));
            break;
        }
    }

    let (entry, _reg_path) = found_entry.with_context(|| {
        format!(
            "No overlay found for {}. Overlay the file first.",
            abs_path.display()
        )
    })?;

    // Read the current (overlaid/modified) content
    let modified_content = fs::read(&abs_path)
        .with_context(|| format!("Failed to read overlaid file: {}", abs_path.display()))?;

    // Read the original content from the store path
    let original_content = if let Some(ref orig) = entry.original_target {
        fs::read(orig).ok()
    } else {
        None
    };

    let home = get_home_dir()?;
    let user_repo = get_user_repo()?;
    let system_repo = get_system_repo(&user_repo);

    let repo = if abs_path.starts_with(&home) {
        &user_repo
    } else {
        &system_repo
    };

    if abs_path.starts_with(&home) {
        if let Some(repo_file) = try_apply_hm(&abs_path, &modified_content, repo)? {
            cmd_remove(&abs_path)?;
            eprintln!(
                "Applied to {}. Run nixos-rebuild to make permanent.",
                repo_file.display()
            );
            return Ok(());
        }
    } else if abs_path.starts_with("/etc/") {
        if let Some(result) = try_apply_etc(&abs_path, &modified_content, &original_content, repo)?
        {
            cmd_remove(&abs_path)?;
            eprintln!("{result}");
            return Ok(());
        }
    }

    apply_with_ai(
        &abs_path,
        &modified_content,
        &original_content,
        &entry,
        repo,
    )?;

    Ok(())
}

fn try_apply_hm(abs_path: &Path, modified_content: &[u8], repo: &Path) -> Result<Option<PathBuf>> {
    let hm_mapping_path = get_hm_mapping_path()?;
    if !hm_mapping_path.exists() {
        return Ok(None);
    }

    let data = fs::read_to_string(&hm_mapping_path)?;
    let mapping: HashMap<String, HmMappingEntry> = serde_json::from_str(&data)?;
    let home = get_home_dir()?;
    let rel = abs_path.strip_prefix(&home)?;

    for (_key, entry) in &mapping {
        if entry.entry_type.as_deref() != Some("repo-source") {
            continue;
        }
        let Some(repo_relative) = &entry.repo_relative else {
            continue;
        };
        let target = entry.target.as_deref().unwrap_or("");
        let target_clean = target.strip_prefix("./").unwrap_or(target);
        let rel_str = rel.to_string_lossy();

        let matches = if entry.recursive.unwrap_or(false) {
            rel_str.starts_with(target_clean)
        } else {
            *rel_str == *target_clean
        };

        if matches {
            let sub_path = if entry.recursive.unwrap_or(false) {
                let after = rel_str.strip_prefix(target_clean).unwrap_or("");
                let after = after.strip_prefix('/').unwrap_or(after);
                if after.is_empty() {
                    repo.join(repo_relative)
                } else {
                    repo.join(repo_relative).join(after)
                }
            } else {
                repo.join(repo_relative)
            };

            if sub_path.exists() || sub_path.parent().is_some_and(|p| p.exists()) {
                fs::write(&sub_path, modified_content)
                    .with_context(|| format!("Failed to write to {}", sub_path.display()))?;
                return Ok(Some(sub_path));
            }
        }
    }

    Ok(None)
}

fn try_apply_etc(
    abs_path: &Path,
    modified_content: &[u8],
    original_content: &Option<Vec<u8>>,
    repo: &Path,
) -> Result<Option<String>> {
    let etc_mapping_path = Path::new("/etc/nix-file-overlay/etc-mapping.json");
    if !etc_mapping_path.exists() {
        return Ok(None);
    }

    let data = fs::read_to_string(etc_mapping_path)?;
    let mapping: HashMap<String, EtcMappingEntry> = serde_json::from_str(&data)?;

    for (_key, entry) in &mapping {
        let Some(p) = &entry.path else { continue };
        if Path::new(p) != abs_path {
            continue;
        }

        let user_files = entry.user_defined_in.as_deref().unwrap_or(&[]);
        if user_files.is_empty() {
            continue;
        }

        if let Some(src) = &entry.source {
            let src_path = Path::new(src);
            if let Some(repo_rel) = extract_repo_relative(src) {
                let repo_file = repo.join(&repo_rel);
                if repo_file.exists() && repo_file.is_file() {
                    fs::write(&repo_file, modified_content)?;
                    return Ok(Some(format!(
                        "Applied to {}. Run nixos-rebuild to make permanent.",
                        repo_file.display()
                    )));
                }
            }

            if src_path.starts_with("/nix/store/") {
                for user_file in user_files {
                    let nix_file = repo.join(user_file);
                    if nix_file.exists() {
                        let diff = generate_diff(original_content, modified_content);
                        return Ok(Some(format!(
                            "File is defined in: {}\n\
                             Changes:\n{}\n\
                             Edit {} to apply the changes permanently.",
                            nix_file.display(),
                            diff,
                            nix_file.display()
                        )));
                    }
                }
            }
        }

        let diff = generate_diff(original_content, modified_content);
        let files_str = user_files
            .iter()
            .map(|f| repo.join(f).to_string_lossy().into_owned())
            .collect::<Vec<_>>()
            .join(", ");
        return Ok(Some(format!(
            "File is defined in NixOS modules: {files_str}\n\
             Changes:\n{diff}\n\
             Edit the module(s) above to apply these changes permanently."
        )));
    }

    Ok(None)
}

fn extract_repo_relative(store_path: &str) -> Option<String> {
    let idx = store_path.find("-source/")?;
    let after = &store_path[idx + "-source/".len()..];
    if after.is_empty() {
        None
    } else {
        Some(after.to_string())
    }
}

fn generate_diff(original: &Option<Vec<u8>>, modified: &[u8]) -> String {
    let orig_str = original
        .as_ref()
        .map(|o| String::from_utf8_lossy(o).into_owned())
        .unwrap_or_else(|| "<original not available>".to_string());
    let mod_str = String::from_utf8_lossy(modified);

    let orig_lines: Vec<&str> = orig_str.lines().collect();
    let mod_lines: Vec<&str> = mod_str.lines().collect();

    let mut diff = String::new();
    let max = orig_lines.len().max(mod_lines.len());
    for i in 0..max {
        let orig_line = orig_lines.get(i).copied().unwrap_or("");
        let mod_line = mod_lines.get(i).copied().unwrap_or("");
        if orig_line != mod_line {
            if i < orig_lines.len() {
                diff.push_str(&format!("- {orig_line}\n"));
            }
            if i < mod_lines.len() {
                diff.push_str(&format!("+ {mod_line}\n"));
            }
        }
    }

    if diff.is_empty() {
        "(no changes detected)".to_string()
    } else {
        diff
    }
}

fn apply_with_ai(
    abs_path: &Path,
    modified_content: &[u8],
    original_content: &Option<Vec<u8>>,
    entry: &OverlayEntry,
    repo: &Path,
) -> Result<()> {
    let diff = generate_diff(original_content, modified_content);

    let mut context_parts = vec![
        format!("File: {}", abs_path.display()),
        format!("Repository: {}", repo.display()),
    ];

    if let Some(ref orig) = entry.original_target {
        context_parts.push(format!("Original store path: {orig}"));
    }
    if let Some(ref mk) = entry.mapping_key {
        context_parts.push(format!("Mapping key: {mk}"));
    }
    if let Some(ref mt) = entry.mapping_type {
        context_parts.push(format!("Mapping type: {mt}"));
    }

    let prompt = format!(
        "The Nix-managed file at {} has been modified with a temporary overlay. \
         The NixOS/home-manager configuration repository is at {}. \
         {}\
         Find the relevant NixOS or home-manager configuration that generates or manages \
         this file and update it to reflect these changes:\n\n{diff}",
        abs_path.display(),
        repo.display(),
        if let Some(ref orig) = entry.original_target {
            format!("The original file was a symlink to {orig}. ")
        } else {
            String::new()
        },
    );

    let cmd_var = std::env::var("NIX_FILE_OVERLAY_CMD");

    match cmd_var {
        Ok(cmd) if cmd.is_empty() => {
            print_guidance(&context_parts, &diff);
        }
        Ok(cmd) => {
            eprintln!("Running custom apply command...");
            let status = Command::new("sh")
                .args(["-c", &format!("{cmd} \"$1\""), "--", &prompt])
                .status()
                .with_context(|| format!("Failed to run custom command: {cmd}"))?;
            if !status.success() {
                eprintln!("Custom command exited with non-zero status");
            }
        }
        Err(_) => {
            if command_exists("opencode") {
                eprintln!("Invoking opencode to find and update the configuration...");
                let status = Command::new("opencode")
                    .args(["run", &prompt])
                    .current_dir(repo)
                    .status()
                    .context("Failed to run opencode")?;
                if !status.success() {
                    eprintln!("opencode exited with non-zero status");
                }
            } else {
                print_guidance(&context_parts, &diff);
            }
        }
    }

    Ok(())
}

fn print_guidance(context: &[String], diff: &str) {
    eprintln!("\nCould not automatically apply changes. Manual steps needed:\n");
    for line in context {
        eprintln!("  {line}");
    }
    eprintln!("\nChanges made:");
    eprintln!("{diff}");
    eprintln!(
        "\nFind the NixOS or home-manager option that generates this file \
         and update it to match the changes above."
    );
}

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn get_user_repo() -> Result<PathBuf> {
    Ok(std::env::var("NIX_FILE_OVERLAY_USER_REPO")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            get_home_dir()
                .unwrap_or_else(|_| PathBuf::from("/root"))
                .join(".nixos")
        }))
}

fn get_system_repo(user_repo: &Path) -> PathBuf {
    std::env::var("NIX_FILE_OVERLAY_SYSTEM_REPO")
        .map(PathBuf::from)
        .unwrap_or_else(|_| user_repo.to_path_buf())
}

// ── Restore command ──────────────────────────────────────────────────

fn cmd_restore(registry_path: Option<&Path>) -> Result<()> {
    let registries: Vec<PathBuf> = if let Some(p) = registry_path {
        vec![p.to_path_buf()]
    } else {
        let mut paths = Vec::new();
        paths.push(get_system_data_dir().join("registry.json"));
        if let Ok(data_dir) = get_data_dir() {
            paths.push(data_dir.join("registry.json"));
        }
        paths
    };

    let mut restored = 0;
    let mut stale = 0;

    for reg_path in &registries {
        let mut registry = match load_registry(reg_path) {
            Ok(r) => r,
            Err(_) => continue,
        };

        let mut to_remove = Vec::new();

        for (path_str, entry) in &registry {
            if !entry.persistent {
                continue;
            }

            let path = Path::new(path_str);

            if !entry.stored_copy.exists() {
                eprintln!(
                    "Warning: stored copy missing for {}, removing stale entry",
                    path_str
                );
                to_remove.push(path_str.clone());
                stale += 1;
                continue;
            }

            if is_bind_mounted(path).unwrap_or(false) {
                continue;
            }

            if !path.exists() && !path.is_symlink() {
                eprintln!(
                    "Warning: path {} no longer exists, removing stale entry",
                    path_str
                );
                to_remove.push(path_str.clone());
                stale += 1;
                continue;
            }

            match run_sudo_mount(&entry.stored_copy, path) {
                Ok(()) => restored += 1,
                Err(e) => eprintln!("Warning: failed to restore {}: {e}", path_str),
            }
        }

        for key in &to_remove {
            registry.remove(key);
        }
        if !to_remove.is_empty() {
            save_registry(reg_path, &registry).ok();
        }
    }

    if restored > 0 || stale > 0 {
        eprintln!("Restore complete: {restored} restored, {stale} stale entries removed");
    }

    Ok(())
}

// ── libc binding ─────────────────────────────────────────────────────

mod libc {
    unsafe extern "C" {
        pub unsafe fn getuid() -> u32;
    }
}
