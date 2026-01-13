use std::collections::HashSet;
use thiserror::Error;
use tokio::sync::mpsc;
use tokio_udev::MonitorBuilder;

/// The AMD iGPU internal display - any other output is from NVIDIA
const IGPU_OUTPUT: &str = "eDP-1";

#[derive(Debug, Clone)]
pub enum HotplugEvent {
    DisplayConnected(String),
    DisplayDisconnected(String),
}

#[derive(Error, Debug)]
pub enum HotplugError {
    #[error("Failed to create udev monitor: {0}")]
    MonitorError(#[from] std::io::Error),
}

/// Check if an output is an external display (not the internal iGPU display)
fn is_external_output(output: &str) -> bool {
    output != IGPU_OUTPUT
}

/// Check if any external displays are currently connected
pub fn has_connected_display() -> bool {
    if let Ok(entries) = std::fs::read_dir("/sys/class/drm") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            // Skip internal display and non-connector entries
            if !name.contains('-') || name.contains(IGPU_OUTPUT) {
                continue;
            }
            
            let status_path = entry.path().join("status");
            if let Ok(status) = std::fs::read_to_string(&status_path) {
                if status.trim() == "connected" {
                    return true;
                }
            }
        }
    }
    false
}

/// Get set of currently connected external displays
pub fn get_connected_displays() -> HashSet<String> {
    let mut connected = HashSet::new();
    
    if let Ok(entries) = std::fs::read_dir("/sys/class/drm") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            // Skip non-connector entries
            if !name.contains('-') {
                continue;
            }
            
            // Extract connector name (e.g., "DP-1" from "card1-DP-1")
            let connector = if let Some(c) = name.strip_prefix("card0-") {
                c
            } else if let Some(c) = name.strip_prefix("card1-") {
                c
            } else {
                continue;
            };
            
            // Skip internal display
            if !is_external_output(connector) {
                continue;
            }
            
            let status_path = entry.path().join("status");
            if let Ok(status) = std::fs::read_to_string(&status_path) {
                if status.trim() == "connected" {
                    connected.insert(connector.to_string());
                }
            }
        }
    }
    
    connected
}

/// Start monitoring for display hotplug events (blocking, runs in dedicated thread)
pub fn monitor_blocking(tx: mpsc::Sender<HotplugEvent>) -> Result<(), HotplugError> {
    let builder = MonitorBuilder::new()?
        .match_subsystem("drm")?;

    let socket = builder.listen()?;

    log::info!("Started display hotplug monitor");

    // Track connected displays to detect changes
    let mut known_connected = get_connected_displays();
    log::debug!("Initially connected displays: {:?}", known_connected);

    // Use synchronous iteration
    let mut iter = socket.iter();
    loop {
        match iter.next() {
            Some(event) => {
                let devpath = event.devpath().to_string_lossy().to_string();

                // Extract connector name from devpath (e.g., "DP-1" from ".../card1-DP-1")
                let connector = devpath
                    .rsplit('/')
                    .next()
                    .and_then(|name| {
                        name.strip_prefix("card0-")
                            .or_else(|| name.strip_prefix("card1-"))
                    });

                if let Some(output) = connector {
                    // Skip internal display
                    if !is_external_output(output) {
                        continue;
                    }

                    let output = output.to_string();

                    // Check current connection status by scanning sysfs
                    // (the connector could be on card0 or card1)
                    let status = ["card0", "card1"]
                        .iter()
                        .find_map(|card| {
                            let path = format!("/sys/class/drm/{}-{}/status", card, output);
                            std::fs::read_to_string(&path).ok()
                        });

                    if let Some(status) = status {
                        let is_connected = status.trim() == "connected";
                        let was_connected = known_connected.contains(&output);

                        if is_connected && !was_connected {
                            log::info!("Display connected: {}", output);
                            known_connected.insert(output.clone());
                            let _ = tx.blocking_send(HotplugEvent::DisplayConnected(output));
                        } else if !is_connected && was_connected {
                            log::info!("Display disconnected: {}", output);
                            known_connected.remove(&output);
                            let _ = tx.blocking_send(HotplugEvent::DisplayDisconnected(output));
                        }
                    }
                }
            }
            None => {
                log::warn!("Udev monitor iterator ended");
                break;
            }
        }
    }

    Ok(())
}
