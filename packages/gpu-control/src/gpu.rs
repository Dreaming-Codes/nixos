use std::fs;
use std::path::Path;
use std::process::Command;
use thiserror::Error;

const NVIDIA_GPU_PCI: &str = "0000:01:00.0";
const NVIDIA_AUDIO_PCI: &str = "0000:01:00.1";
const PARENT_BRIDGE: &str = "0000:00:01.1";
const SOFT_DISABLED_MARKER: &str = "/run/gpu-soft-disabled";

const NVIDIA_MODULES: &[&str] = &["nvidia", "nvidia_modeset", "nvidia_drm", "nvidia_uvm"];

#[derive(Error, Debug)]
pub enum GpuError {
    #[error("GPU operation failed: {0}")]
    OperationFailed(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Processes are using the GPU: {0:?}")]
    ProcessesBlocking(Vec<ProcessInfo>),
    #[error("Not in offload mode - GPU control not available")]
    NotOffloadMode,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct GpuStatus {
    pub present: bool,
    pub modules_loaded: bool,
    pub power_state: Option<String>,
    pub soft_disabled_at_boot: bool,
    pub blocking_processes: Vec<ProcessInfo>,
    pub specialisation: String,
    pub can_control: bool,
}

/// Check if we're in an offload mode where GPU control is allowed
pub fn is_offload_mode() -> bool {
    let spec = get_current_specialisation();
    // Control allowed in default (offload) and prime-ready modes
    matches!(spec.as_str(), "default" | "prime-ready" | "")
}

/// Get the current NixOS specialisation
pub fn get_current_specialisation() -> String {
    // Check kernel cmdline for specialisation
    if let Ok(cmdline) = fs::read_to_string("/proc/cmdline") {
        for part in cmdline.split_whitespace() {
            if let Some(_spec) = part.strip_prefix("systemd.machine_id=") {
                // This isn't the right approach, let's check the symlink
                break;
            }
        }
    }

    // Check the current system profile
    let profile_path = "/run/current-system";
    if let Ok(target) = fs::read_link(profile_path) {
        let target_str = target.to_string_lossy();
        if target_str.contains("specialisation") {
            // Extract specialisation name from path
            if let Some(name) = target_str.split("specialisation-").last() {
                if let Some(name) = name.split('/').next() {
                    return name.to_string();
                }
            }
        }
    }

    // Check for booted system specialisation marker
    if let Ok(spec) = fs::read_to_string("/run/current-system/specialisation-name") {
        return spec.trim().to_string();
    }

    "default".to_string()
}

/// Check if GPU PCI device is present in the system
pub fn is_gpu_present() -> bool {
    Path::new(&format!("/sys/bus/pci/devices/{}", NVIDIA_GPU_PCI)).exists()
}

/// Check if NVIDIA modules are loaded
pub fn are_modules_loaded() -> bool {
    if let Ok(modules) = fs::read_to_string("/proc/modules") {
        return modules.lines().any(|line| line.starts_with("nvidia "));
    }
    false
}

/// Get GPU power state (if available)
pub fn get_power_state() -> Option<String> {
    let power_path = format!("/sys/bus/pci/devices/{}/power_state", NVIDIA_GPU_PCI);
    fs::read_to_string(power_path).ok().map(|s| s.trim().to_string())
}

/// Check if GPU was soft-disabled at boot
pub fn was_soft_disabled() -> bool {
    Path::new(SOFT_DISABLED_MARKER).exists()
}

/// Get processes using the NVIDIA GPU
pub fn get_blocking_processes() -> Vec<ProcessInfo> {
    let mut processes = Vec::new();

    // Try nvidia-smi first
    if let Ok(output) = Command::new("nvidia-smi")
        .args(["--query-compute-apps=pid,process_name", "--format=csv,noheader,nounits"])
        .output()
    {
        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                let parts: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
                if parts.len() >= 2 {
                    if let Ok(pid) = parts[0].parse() {
                        processes.push(ProcessInfo {
                            pid,
                            name: parts[1].to_string(),
                        });
                    }
                }
            }
        }
    }

    // Also check for processes with nvidia devices open via /proc
    if let Ok(entries) = fs::read_dir("/proc") {
        for entry in entries.flatten() {
            if let Ok(pid) = entry.file_name().to_string_lossy().parse::<u32>() {
                let fd_path = format!("/proc/{}/fd", pid);
                if let Ok(fds) = fs::read_dir(&fd_path) {
                    for fd in fds.flatten() {
                        if let Ok(link) = fs::read_link(fd.path()) {
                            let link_str = link.to_string_lossy();
                            if link_str.contains("/dev/nvidia") || link_str.contains("/dev/dri/card") {
                                // Check if it's actually the nvidia card
                                if link_str.contains("nvidia") {
                                    // Get process name
                                    let comm_path = format!("/proc/{}/comm", pid);
                                    let name = fs::read_to_string(&comm_path)
                                        .map(|s| s.trim().to_string())
                                        .unwrap_or_else(|_| "unknown".to_string());

                                    // Avoid duplicates
                                    if !processes.iter().any(|p| p.pid == pid) {
                                        processes.push(ProcessInfo { pid, name });
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    processes
}

/// Get full GPU status
pub fn get_status() -> GpuStatus {
    let specialisation = get_current_specialisation();
    let can_control = is_offload_mode();

    GpuStatus {
        present: is_gpu_present(),
        modules_loaded: are_modules_loaded(),
        power_state: get_power_state(),
        soft_disabled_at_boot: was_soft_disabled(),
        blocking_processes: get_blocking_processes(),
        specialisation,
        can_control,
    }
}

/// Enable the GPU
pub fn enable() -> Result<(), GpuError> {
    if !is_offload_mode() {
        return Err(GpuError::NotOffloadMode);
    }

    log::info!("Enabling NVIDIA GPU...");

    // If GPU is already present and modules loaded, nothing to do
    if is_gpu_present() && are_modules_loaded() {
        log::info!("GPU already enabled");
        return Ok(());
    }

    // Rescan PCI bus to bring back the device
    if !is_gpu_present() {
        log::info!("Rescanning PCI bus...");
        run_privileged("tee", &["/sys/bus/pci/devices/{}/rescan", "1"], PARENT_BRIDGE)?;

        // Wait for device to appear
        for _ in 0..50 {
            if is_gpu_present() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }

        if !is_gpu_present() {
            return Err(GpuError::OperationFailed("GPU did not appear after rescan".to_string()));
        }
    }

    // Load NVIDIA modules
    log::info!("Loading NVIDIA modules...");
    for module in NVIDIA_MODULES {
        run_sudo("modprobe", &[module])?;
    }

    // Wait for modules to load
    std::thread::sleep(std::time::Duration::from_millis(500));

    if !are_modules_loaded() {
        return Err(GpuError::OperationFailed("Failed to load NVIDIA modules".to_string()));
    }

    log::info!("GPU enabled successfully");
    Ok(())
}

/// Disable the GPU
pub fn disable(kill: bool, force: bool) -> Result<(), GpuError> {
    if !is_offload_mode() {
        return Err(GpuError::NotOffloadMode);
    }

    log::info!("Disabling NVIDIA GPU...");

    // Check for blocking processes
    let blocking = get_blocking_processes();
    if !blocking.is_empty() {
        if kill {
            log::info!("Killing {} blocking processes...", blocking.len());
            for proc in &blocking {
                let _ = Command::new("kill").arg("-9").arg(proc.pid.to_string()).status();
            }
            std::thread::sleep(std::time::Duration::from_millis(500));
        } else if !force {
            return Err(GpuError::ProcessesBlocking(blocking));
        } else {
            log::warn!("Force disabling with {} blocking processes", blocking.len());
        }
    }

    // Unload NVIDIA modules in reverse order
    log::info!("Unloading NVIDIA modules...");
    for module in NVIDIA_MODULES.iter().rev() {
        let _ = run_sudo("modprobe", &["-r", module]);
    }

    // Wait a bit for modules to unload
    std::thread::sleep(std::time::Duration::from_millis(500));

    // Remove GPU from PCI bus
    if is_gpu_present() {
        log::info!("Removing GPU from PCI bus...");
        // Remove audio device first
        let audio_remove = format!("/sys/bus/pci/devices/{}/remove", NVIDIA_AUDIO_PCI);
        if Path::new(&audio_remove).exists() {
            let _ = write_sysfs(&audio_remove, "1");
        }

        // Remove GPU device
        let gpu_remove = format!("/sys/bus/pci/devices/{}/remove", NVIDIA_GPU_PCI);
        write_sysfs(&gpu_remove, "1")?;

        // Wait for device to disappear
        for _ in 0..50 {
            if !is_gpu_present() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
    }

    if is_gpu_present() {
        return Err(GpuError::OperationFailed("GPU still present after removal".to_string()));
    }

    log::info!("GPU disabled successfully");
    Ok(())
}

fn run_sudo(cmd: &str, args: &[&str]) -> Result<(), GpuError> {
    let status = Command::new("sudo")
        .arg(cmd)
        .args(args)
        .status()
        .map_err(|e| GpuError::OperationFailed(format!("Failed to run {}: {}", cmd, e)))?;

    if !status.success() {
        return Err(GpuError::OperationFailed(format!(
            "{} failed with exit code {:?}",
            cmd,
            status.code()
        )));
    }

    Ok(())
}

fn run_privileged(cmd: &str, args: &[&str], device: &str) -> Result<(), GpuError> {
    // Build the actual path
    let actual_args: Vec<String> = args
        .iter()
        .map(|a| a.replace("{}", device))
        .collect();

    let args_refs: Vec<&str> = actual_args.iter().map(|s| s.as_str()).collect();
    run_sudo(cmd, &args_refs)
}

fn write_sysfs(path: &str, value: &str) -> Result<(), GpuError> {
    // Use tee via sudo to write to sysfs
    let mut child = Command::new("sudo")
        .arg("tee")
        .arg(path)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .spawn()
        .map_err(|e| GpuError::OperationFailed(format!("Failed to run tee: {}", e)))?;

    if let Some(stdin) = child.stdin.as_mut() {
        use std::io::Write;
        stdin.write_all(value.as_bytes())?;
    }

    let status = child.wait()?;
    if !status.success() {
        return Err(GpuError::OperationFailed(format!(
            "Failed to write to {}",
            path
        )));
    }

    Ok(())
}
