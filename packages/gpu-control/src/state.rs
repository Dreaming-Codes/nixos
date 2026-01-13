use serde::{Deserialize, Serialize};
use std::path::Path;
use thiserror::Error;

const STATE_FILE: &str = "/run/gpu-control/state.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GpuState {
    /// GPU is enabled, user explicitly wants it on
    Enabled,
    /// GPU is disabled
    Disabled,
    /// GPU is enabled due to display hotplug, will disable on disconnect
    AutoEnabled,
    /// GPU should be off but blocked by processes, daemon retries periodically
    PendingDisable,
}

impl Default for GpuState {
    fn default() -> Self {
        Self::Disabled
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DaemonState {
    pub gpu_state: GpuState,
    /// State before auto-enable (to restore after display disconnect)
    pub previous_state: Option<GpuState>,
    /// Notification ID for pending disable notification
    pub pending_notification_id: Option<u32>,
}

#[derive(Error, Debug)]
pub enum StateError {
    #[error("Failed to read state file: {0}")]
    ReadError(#[from] std::io::Error),
    #[error("Failed to parse state file: {0}")]
    ParseError(#[from] serde_json::Error),
}

impl DaemonState {
    pub fn load() -> Result<Self, StateError> {
        let path = Path::new(STATE_FILE);
        if !path.exists() {
            return Ok(Self::default());
        }
        let contents = std::fs::read_to_string(path)?;
        let state = serde_json::from_str(&contents)?;
        Ok(state)
    }

    pub fn save(&self) -> Result<(), StateError> {
        let path = Path::new(STATE_FILE);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let contents = serde_json::to_string_pretty(self)?;
        std::fs::write(path, contents)?;
        Ok(())
    }
}
