use hyprland::event_listener::AsyncEventListener;
use serde::{Deserialize, Serialize};
use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::net::UnixListener;
use tokio::sync::{mpsc, RwLock};
use tokio::time::interval;

const POLL_INTERVAL_SECS: u64 = 30;
const RAZER_SOCKET_PATH: &str = "/tmp/razercontrol-socket";

#[derive(Debug, Clone, Copy)]
struct Rgb(u8, u8, u8);

impl Rgb {
    const GREEN: Self = Self(0, 255, 0);
    const RED: Self = Self(255, 0, 0);
    const ORANGE: Self = Self(255, 165, 0);
    const GRAY: Self = Self(128, 128, 128);
    const BLUE: Self = Self(0, 0, 255);
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum CiStatus {
    Success,
    Failure,
    Pending,
    Unknown,
}

impl CiStatus {
    fn color(&self) -> Rgb {
        match self {
            Self::Success => Rgb::GREEN,
            Self::Failure => Rgb::RED,
            Self::Pending => Rgb::ORANGE,
            Self::Unknown => Rgb::GRAY,
        }
    }
}

#[derive(Deserialize)]
struct CheckRuns {
    check_runs: Vec<CheckRun>,
}

#[derive(Deserialize)]
struct CheckRun {
    status: String,
    conclusion: Option<String>,
}

// Razer daemon protocol (must match daemon's comms.rs)
#[derive(Serialize, Deserialize, Debug)]
#[allow(dead_code)]
enum DaemonCommand {
    SetFanSpeed { ac: usize, rpm: i32 },
    GetFanSpeed { ac: usize },
    SetPowerMode { ac: usize, pwr: u8, cpu: u8, gpu: u8 },
    GetPwrLevel { ac: usize },
    GetCPUBoost { ac: usize },
    GetGPUBoost { ac: usize },
    SetLogoLedState { ac: usize, logo_state: u8 },
    GetLogoLedState { ac: usize },
    GetKeyboardRGB { layer: i32 },
    SetEffect { name: String, params: Vec<u8> },
    SetStandardEffect { name: String, params: Vec<u8> },
    SetBrightness { ac: usize, val: u8 },
    SetIdle { ac: usize, val: u32 },
    GetBrightness { ac: usize },
    SetSync { sync: bool },
    GetSync(),
    SetBatteryHealthOptimizer { is_on: bool, threshold: u8 },
    GetBatteryHealthOptimizer(),
    GetDeviceName,
}

#[derive(Serialize, Deserialize, Debug)]
#[allow(dead_code)]
enum DaemonResponse {
    SetFanSpeed { result: bool },
    GetFanSpeed { rpm: i32 },
    SetPowerMode { result: bool },
    GetPwrLevel { pwr: u8 },
    GetCPUBoost { cpu: u8 },
    GetGPUBoost { gpu: u8 },
    SetLogoLedState { result: bool },
    GetLogoLedState { logo_state: u8 },
    GetKeyboardRGB { layer: i32, rgbdata: Vec<u8> },
    SetEffect { result: bool },
    SetStandardEffect { result: bool },
    SetBrightness { result: bool },
    SetIdle { result: bool },
    GetBrightness { result: u8 },
    SetSync { result: bool },
    GetSync { sync: bool },
    SetBatteryHealthOptimizer { result: bool },
    GetBatteryHealthOptimizer { is_on: bool, threshold: u8 },
    GetDeviceName { name: String },
}

#[derive(Debug, Clone, PartialEq)]
struct RepoInfo {
    repo: String,
    sha: String,
}

/// Extract owner/repo from git remote URL
fn parse_github_remote(url: &str) -> Option<String> {
    let url = url.trim();
    if let Some(rest) = url.strip_prefix("git@github.com:") {
        Some(rest.trim_end_matches(".git").to_string())
    } else if let Some(rest) = url.strip_prefix("https://github.com/") {
        Some(rest.trim_end_matches(".git").to_string())
    } else {
        None
    }
}

/// Get current repo info from a directory
fn get_repo_info(dir: &Path) -> Option<RepoInfo> {
    let remote = Command::new("git")
        .args(["remote", "get-url", "origin"])
        .current_dir(dir)
        .output()
        .ok()?;

    let commit = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(dir)
        .output()
        .ok()?;

    if !remote.status.success() || !commit.status.success() {
        return None;
    }

    let remote_url = String::from_utf8_lossy(&remote.stdout);
    let sha = String::from_utf8_lossy(&commit.stdout).trim().to_string();
    let repo = parse_github_remote(&remote_url)?;

    Some(RepoInfo { repo, sha })
}

async fn get_commit_status(
    client: &reqwest::Client,
    repo: &str,
    sha: &str,
    token: &str,
) -> CiStatus {
    let url = format!("https://api.github.com/repos/{repo}/commits/{sha}/check-runs");

    let Ok(resp) = client
        .get(&url)
        .header("Authorization", format!("Bearer {token}"))
        .header("User-Agent", "ci-keyboard-leds")
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
    else {
        return CiStatus::Unknown;
    };

    let Ok(runs) = resp.json::<CheckRuns>().await else {
        return CiStatus::Unknown;
    };

    if runs.check_runs.is_empty() {
        return CiStatus::Unknown;
    }

    let mut has_pending = false;
    let mut has_failure = false;

    for run in &runs.check_runs {
        if run.status != "completed" {
            has_pending = true;
        } else {
            match run.conclusion.as_deref() {
                Some("failure") | Some("cancelled") | Some("timed_out") => has_failure = true,
                _ => {}
            }
        }
    }

    if has_pending {
        CiStatus::Pending
    } else if has_failure {
        CiStatus::Failure
    } else {
        CiStatus::Success
    }
}

/// Send command to razer daemon and get response
fn send_to_razer_daemon(command: DaemonCommand) -> Option<DaemonResponse> {
    let mut sock = UnixStream::connect(RAZER_SOCKET_PATH).ok()?;
    let encoded = bincode::serialize(&command).ok()?;
    sock.write_all(&encoded).ok()?;

    let mut buf = [0u8; 4096];
    let n = sock.read(&mut buf).ok()?;
    if n == 0 {
        return None;
    }
    bincode::deserialize(&buf[..n]).ok()
}

/// Set Razer keyboard to static color (whole keyboard)
fn set_razer_static_color(color: Rgb) -> bool {
    let cmd = DaemonCommand::SetStandardEffect {
        name: "static".to_string(),
        params: vec![color.0, color.1, color.2],
    };
    let response = send_to_razer_daemon(cmd);
    eprintln!("[DEBUG] Razer response: {:?}", response);
    matches!(
        response,
        Some(DaemonResponse::SetStandardEffect { result: true })
    )
}

/// Check if razer daemon is available
fn razer_daemon_available() -> bool {
    std::fs::metadata(RAZER_SOCKET_PATH).is_ok()
}

// TODO: Keychron Q6 Pro support requires custom QMK firmware with RAW HID handler
// to control individual key LEDs. Stock firmware doesn't support this protocol.

/// Update all connected keyboards with the given color
fn update_keyboards(color: Rgb) {
    // Update Razer laptop keyboard (if available)
    if razer_daemon_available() {
        if set_razer_static_color(color) {
            eprintln!("[DEBUG] Razer: updated successfully");
        } else {
            eprintln!("[DEBUG] Razer: failed to update");
        }
    } else {
        eprintln!("[DEBUG] Razer: daemon not available");
    }

    // TODO: Keychron Q6 Pro support requires custom QMK firmware
}

/// Get the socket path for CWD notifications
fn get_cwd_socket_path() -> String {
    let xdg_runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    format!("{}/ci-keyboard-leds.sock", xdg_runtime)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let token = env::var("GITHUB_TOKEN").expect("GITHUB_TOKEN required");

    let http_client = reqwest::Client::new();

    println!("CI Keyboard LEDs starting...");
    println!(
        "  Razer daemon: {}",
        if razer_daemon_available() {
            "available"
        } else {
            "not found"
        }
    );

    // Shared state for current CWD (updated by fish via socket)
    let current_cwd: Arc<RwLock<Option<String>>> = Arc::new(RwLock::new(None));

    let mut last_repo_info: Option<RepoInfo> = None;
    let mut last_status: Option<CiStatus> = None;

    // Channel for triggering updates
    let (tx, mut rx) = mpsc::channel::<()>(16);

    // Setup Unix socket for CWD notifications from fish
    let socket_path = get_cwd_socket_path();
    // Remove stale socket if exists
    let _ = std::fs::remove_file(&socket_path);
    let listener = UnixListener::bind(&socket_path)?;
    println!("  CWD socket: {}", socket_path);

    // Spawn socket listener for CWD updates from fish
    let tx_socket = tx.clone();
    let cwd_for_socket = Arc::clone(&current_cwd);
    tokio::spawn(async move {
        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let tx = tx_socket.clone();
                    let cwd = Arc::clone(&cwd_for_socket);
                    tokio::spawn(async move {
                        let reader = BufReader::new(stream);
                        let mut lines = reader.lines();
                        while let Ok(Some(line)) = lines.next_line().await {
                            let path = line.trim().to_string();
                            if !path.is_empty() {
                                eprintln!("[DEBUG] Received CWD from fish: {}", path);
                                *cwd.write().await = Some(path);
                                let _ = tx.send(()).await;
                            }
                        }
                    });
                }
                Err(e) => {
                    eprintln!("Socket accept error: {}", e);
                }
            }
        }
    });

    // Spawn Hyprland event listener using hyprland-rs
    let tx_hypr = tx.clone();
    tokio::spawn(async move {
        loop {
            let tx_inner = tx_hypr.clone();
            let mut listener = AsyncEventListener::new();

            listener.add_active_window_changed_handler(move |_| {
                let tx = tx_inner.clone();
                Box::pin(async move {
                    let _ = tx.send(()).await;
                })
            });

            println!("  Hyprland IPC: connected");
            if let Err(e) = listener.start_listener_async().await {
                eprintln!("  Hyprland IPC error: {e}, reconnecting...");
            }

            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    });

    // Spawn periodic poll for CI status changes (in case CI finishes while we're focused)
    let tx_poll = tx.clone();
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_secs(POLL_INTERVAL_SECS));
        loop {
            interval.tick().await;
            let _ = tx_poll.send(()).await;
        }
    });

    // Trigger initial update
    let _ = tx.send(()).await;

    // Main update loop
    loop {
        rx.recv().await;

        // Debounce rapid events
        tokio::time::sleep(Duration::from_millis(50)).await;
        while rx.try_recv().is_ok() {}

        // Get current CWD from shared state
        let cwd = current_cwd.read().await.clone();
        eprintln!("[DEBUG] Current CWD: {:?}", cwd);

        let current_info = cwd.and_then(|cwd| {
            let info = get_repo_info(Path::new(&cwd));
            eprintln!("[DEBUG] Repo info for {}: {:?}", cwd, info);
            info
        });

        // Handle case where we're not in a git repo with CI
        let Some(ref info) = current_info else {
            // Not in a git repo - set keyboard to blue
            if last_repo_info.is_some() || last_status.is_some() {
                eprintln!("[DEBUG] No repo info, setting keyboard to blue");
                println!("(no repo) -> blue");
                update_keyboards(Rgb::BLUE);
                last_repo_info = None;
                last_status = None;
            }
            continue;
        };

        // Update repo info if we got something new
        let repo_changed = Some(info.clone()) != last_repo_info;
        last_repo_info = Some(info.clone());

        // Fetch CI status
        let status = get_commit_status(&http_client, &info.repo, &info.sha, &token).await;

        // Update LEDs if status changed or repo changed
        if last_status != Some(status) || repo_changed {
            let color = status.color();
            println!(
                "{}@{} -> {:?}",
                info.repo,
                &info.sha[..7.min(info.sha.len())],
                status
            );

            update_keyboards(color);
            last_status = Some(status);
        }
    }
}
