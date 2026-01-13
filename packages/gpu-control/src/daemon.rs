use std::time::Duration;
use thiserror::Error;
use tokio::sync::mpsc;
use tokio::time::interval;

use crate::gpu::{self, GpuError};
use crate::hotplug::{self, HotplugEvent};
use crate::ipc::{self, Request, Response};
use crate::notify;
use crate::state::{DaemonState, GpuState};

const RETRY_INTERVAL_SECS: u64 = 5;

#[derive(Error, Debug)]
pub enum DaemonError {
    #[error("IPC error: {0}")]
    IpcError(#[from] crate::ipc::IpcError),
}

pub async fn run() -> Result<(), DaemonError> {
    log::info!("Starting gpu-control daemon");

    // Check if we're in a mode where the daemon should run
    if !gpu::is_offload_mode() {
        log::warn!("Not in offload mode - daemon will only provide status");
    }

    // Load or initialize state
    let mut state = DaemonState::load().unwrap_or_default();

    // Check initial GPU state
    if gpu::is_gpu_present() && gpu::are_modules_loaded() {
        if state.gpu_state == GpuState::Disabled {
            // GPU is on but we thought it was off - sync state
            state.gpu_state = GpuState::Enabled;
        }
    } else if state.gpu_state == GpuState::Enabled || state.gpu_state == GpuState::AutoEnabled {
        // GPU is off but we thought it was on - sync state
        state.gpu_state = GpuState::Disabled;
    }

    let _ = state.save();

    // Create IPC listener
    let listener = ipc::create_listener().await?;
    log::info!("IPC socket ready at {}", ipc::SOCKET_PATH);

    // Create channel for hotplug events
    let (hotplug_tx, mut hotplug_rx) = mpsc::channel::<HotplugEvent>(16);

    // Spawn hotplug monitor in a blocking thread (udev types aren't Send)
    std::thread::spawn(move || {
        if let Err(e) = hotplug::monitor_blocking(hotplug_tx) {
            log::error!("Hotplug monitor error: {}", e);
        }
    });

    // Retry timer for pending disable
    let mut retry_interval = interval(Duration::from_secs(RETRY_INTERVAL_SECS));
    retry_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        tokio::select! {
            // Handle IPC requests
            Ok((mut stream, _)) = listener.accept() => {
                match ipc::read_request(&mut stream).await {
                    Ok(request) => {
                        let response = handle_request(request, &mut state).await;
                        if let Err(e) = ipc::send_response(&mut stream, &response).await {
                            log::error!("Failed to send response: {}", e);
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to read request: {}", e);
                    }
                }
            }

            // Handle hotplug events
            Some(event) = hotplug_rx.recv() => {
                handle_hotplug_event(event, &mut state).await;
            }

            // Retry pending disable
            _ = retry_interval.tick() => {
                if state.gpu_state == GpuState::PendingDisable {
                    retry_disable(&mut state).await;
                }
            }
        }
    }
}

async fn handle_request(request: Request, state: &mut DaemonState) -> Response {
    match request {
        Request::Status => {
            let status = gpu::get_status();
            Response::Status {
                status,
                daemon_state: Some(state.gpu_state),
            }
        }

        Request::Enable => {
            if !gpu::is_offload_mode() {
                return Response::Error {
                    message: "GPU control not available in this mode".to_string(),
                };
            }

            match gpu::enable() {
                Ok(()) => {
                    state.gpu_state = GpuState::Enabled;
                    state.previous_state = None;
                    let _ = state.save();
                    Response::Success {
                        message: "GPU enabled".to_string(),
                    }
                }
                Err(e) => Response::Error {
                    message: e.to_string(),
                },
            }
        }

        Request::Disable { kill, force } => {
            if !gpu::is_offload_mode() {
                return Response::Error {
                    message: "GPU control not available in this mode".to_string(),
                };
            }

            match gpu::disable(kill, force) {
                Ok(()) => {
                    state.gpu_state = GpuState::Disabled;
                    state.previous_state = None;
                    state.pending_notification_id = None;
                    let _ = state.save();
                    Response::Success {
                        message: "GPU disabled".to_string(),
                    }
                }
                Err(GpuError::ProcessesBlocking(processes)) => {
                    Response::ProcessesBlocking { processes }
                }
                Err(e) => Response::Error {
                    message: e.to_string(),
                },
            }
        }

        Request::KeepOn => {
            // User chose to keep GPU on from notification
            if state.gpu_state == GpuState::PendingDisable {
                state.gpu_state = GpuState::Enabled;
                state.previous_state = None;
                if let Some(id) = state.pending_notification_id.take() {
                    let _ = notify::close_notification(id);
                }
                let _ = state.save();
                let _ = notify::disable_cancelled();
            }
            Response::Success {
                message: "GPU will remain enabled".to_string(),
            }
        }

        Request::ForceDisable => {
            // User chose to force disable from notification
            if let Some(id) = state.pending_notification_id.take() {
                let _ = notify::close_notification(id);
            }

            match gpu::disable(false, true) {
                Ok(()) => {
                    state.gpu_state = GpuState::Disabled;
                    state.previous_state = None;
                    let _ = state.save();
                    let _ = notify::gpu_disabled();
                    Response::Success {
                        message: "GPU force disabled".to_string(),
                    }
                }
                Err(e) => Response::Error {
                    message: e.to_string(),
                },
            }
        }
    }
}

async fn handle_hotplug_event(event: HotplugEvent, state: &mut DaemonState) {
    if !gpu::is_offload_mode() {
        log::debug!("Ignoring hotplug event - not in offload mode");
        return;
    }

    match event {
        HotplugEvent::DisplayConnected(output) => {
            log::info!("Display connected: {}", output);

            // Only auto-enable if GPU is currently disabled
            if state.gpu_state == GpuState::Disabled {
                // Save previous state so we can restore it
                state.previous_state = Some(state.gpu_state);

                match gpu::enable() {
                    Ok(()) => {
                        state.gpu_state = GpuState::AutoEnabled;
                        let _ = state.save();
                        let _ = notify::display_connected(&output);
                    }
                    Err(e) => {
                        log::error!("Failed to enable GPU for hotplug: {}", e);
                    }
                }
            }
        }

        HotplugEvent::DisplayDisconnected(output) => {
            log::info!("Display disconnected: {}", output);
            let _ = notify::display_disconnected(&output);

            // Only auto-disable if we auto-enabled
            if state.gpu_state == GpuState::AutoEnabled {
                // Check if there are still other displays connected
                if !hotplug::has_connected_display() {
                    // Try to disable
                    match gpu::disable(false, false) {
                        Ok(()) => {
                            state.gpu_state = state.previous_state.unwrap_or(GpuState::Disabled);
                            state.previous_state = None;
                            let _ = state.save();
                            let _ = notify::gpu_disabled();
                        }
                        Err(GpuError::ProcessesBlocking(processes)) => {
                            // Enter pending disable state
                            state.gpu_state = GpuState::PendingDisable;
                            let _ = state.save();

                            // Show notification with actions
                            match notify::pending_disable(&processes) {
                                Ok(id) => {
                                    state.pending_notification_id = Some(id);
                                    let _ = state.save();
                                }
                                Err(e) => {
                                    log::error!("Failed to show notification: {}", e);
                                }
                            }
                        }
                        Err(e) => {
                            log::error!("Failed to disable GPU: {}", e);
                        }
                    }
                }
            }
        }
    }
}

async fn retry_disable(state: &mut DaemonState) {
    log::debug!("Retrying GPU disable...");

    match gpu::disable(false, false) {
        Ok(()) => {
            log::info!("GPU disabled successfully on retry");
            state.gpu_state = state.previous_state.unwrap_or(GpuState::Disabled);
            state.previous_state = None;

            if let Some(id) = state.pending_notification_id.take() {
                let _ = notify::close_notification(id);
            }

            let _ = state.save();
            let _ = notify::gpu_disabled();
        }
        Err(GpuError::ProcessesBlocking(processes)) => {
            log::debug!("Still {} processes blocking GPU", processes.len());
            // Update notification with current process list
            if let Some(id) = state.pending_notification_id.take() {
                let _ = notify::close_notification(id);
            }
            match notify::pending_disable(&processes) {
                Ok(id) => {
                    state.pending_notification_id = Some(id);
                    let _ = state.save();
                }
                Err(e) => {
                    log::error!("Failed to update notification: {}", e);
                }
            }
        }
        Err(e) => {
            log::error!("Retry disable failed: {}", e);
        }
    }
}
