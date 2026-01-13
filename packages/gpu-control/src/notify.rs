use notify_rust::{Hint, Notification, Timeout, Urgency};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum NotifyError {
    #[error("Notification error: {0}")]
    NotificationError(#[from] notify_rust::error::Error),
}

/// Show a notification that GPU was auto-enabled due to display connection
pub fn display_connected(output: &str) -> Result<(), NotifyError> {
    Notification::new()
        .summary("External Display Connected")
        .body(&format!(
            "Display connected on {}. NVIDIA GPU has been enabled.",
            output
        ))
        .icon("video-display")
        .urgency(Urgency::Normal)
        .timeout(Timeout::Milliseconds(5000))
        .show()?;

    Ok(())
}

/// Show a notification that display was disconnected
pub fn display_disconnected(output: &str) -> Result<(), NotifyError> {
    Notification::new()
        .summary("External Display Disconnected")
        .body(&format!(
            "Display disconnected from {}. GPU will be disabled if no longer needed.",
            output
        ))
        .icon("video-display")
        .urgency(Urgency::Low)
        .timeout(Timeout::Milliseconds(3000))
        .show()?;

    Ok(())
}

/// Show a persistent notification when GPU cannot be disabled due to blocking processes
/// Returns the notification handle for later closing
pub fn pending_disable(processes: &[crate::gpu::ProcessInfo]) -> Result<u32, NotifyError> {
    let process_list: Vec<String> = processes
        .iter()
        .take(5)
        .map(|p| format!("{} ({})", p.name, p.pid))
        .collect();

    let mut body = format!(
        "Cannot disable GPU - {} process(es) are using it:\n{}",
        processes.len(),
        process_list.join("\n")
    );

    if processes.len() > 5 {
        body.push_str(&format!("\n...and {} more", processes.len() - 5));
    }

    let handle = Notification::new()
        .summary("GPU Disable Pending")
        .body(&body)
        .icon("dialog-warning")
        .urgency(Urgency::Normal)
        .timeout(Timeout::Never)
        .hint(Hint::Resident(true))
        .action("force", "Force Disable")
        .action("keep", "Keep GPU On")
        .show()?;

    Ok(handle.id())
}

/// Show notification that GPU has been disabled
pub fn gpu_disabled() -> Result<(), NotifyError> {
    Notification::new()
        .summary("NVIDIA GPU Disabled")
        .body("GPU has been powered off to save battery.")
        .icon("battery")
        .urgency(Urgency::Low)
        .timeout(Timeout::Milliseconds(3000))
        .show()?;

    Ok(())
}

/// Show notification that GPU disable was cancelled
pub fn disable_cancelled() -> Result<(), NotifyError> {
    Notification::new()
        .summary("GPU Disable Cancelled")
        .body("NVIDIA GPU will remain enabled.")
        .icon("video-display")
        .urgency(Urgency::Low)
        .timeout(Timeout::Milliseconds(3000))
        .show()?;

    Ok(())
}

/// Close a notification by ID
pub fn close_notification(id: u32) -> Result<(), NotifyError> {
    // notify-rust doesn't have a direct close API, but we can use the handle
    // For now, we'll just let notifications timeout or be replaced
    // The notification daemon will handle cleanup
    log::debug!("Would close notification {}", id);
    Ok(())
}
