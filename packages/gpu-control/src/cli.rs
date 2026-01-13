use crate::gpu;
use crate::ipc::{self, Request, Response};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CliError {
    #[error("GPU error: {0}")]
    GpuError(#[from] gpu::GpuError),
    #[error("IPC error: {0}")]
    IpcError(#[from] ipc::IpcError),
    #[error("Operation failed: {0}")]
    OperationFailed(String),
}

/// Show GPU status
pub async fn status(json: bool) -> Result<(), CliError> {
    // Try to get status from daemon first (includes daemon state)
    let response = match ipc::send_request(&Request::Status).await {
        Ok(resp) => resp,
        Err(ipc::IpcError::DaemonNotRunning) => {
            // Daemon not running, get status directly
            let status = gpu::get_status();
            Response::Status {
                status,
                daemon_state: None,
            }
        }
        Err(e) => return Err(e.into()),
    };

    match response {
        Response::Status { status, daemon_state } => {
            if json {
                let output = serde_json::json!({
                    "present": status.present,
                    "modules_loaded": status.modules_loaded,
                    "power_state": status.power_state,
                    "soft_disabled_at_boot": status.soft_disabled_at_boot,
                    "blocking_processes": status.blocking_processes,
                    "specialisation": status.specialisation,
                    "can_control": status.can_control,
                    "daemon_state": daemon_state,
                });
                println!("{}", serde_json::to_string_pretty(&output).unwrap());
            } else {
                println!("NVIDIA GPU Status");
                println!("=================");
                println!("Present:              {}", if status.present { "yes" } else { "no" });
                println!("Modules loaded:       {}", if status.modules_loaded { "yes" } else { "no" });
                if let Some(ref power) = status.power_state {
                    println!("Power state:          {}", power);
                }
                println!("Soft-disabled at boot: {}", if status.soft_disabled_at_boot { "yes" } else { "no" });
                println!("Specialisation:       {}", status.specialisation);
                println!("Can control:          {}", if status.can_control { "yes" } else { "no" });

                if let Some(state) = daemon_state {
                    println!("Daemon state:         {:?}", state);
                } else {
                    println!("Daemon:               not running");
                }

                if !status.blocking_processes.is_empty() {
                    println!("\nBlocking processes:");
                    for proc in &status.blocking_processes {
                        println!("  {} (PID {})", proc.name, proc.pid);
                    }
                }
            }
        }
        Response::Error { message } => {
            return Err(CliError::OperationFailed(message));
        }
        _ => {
            return Err(CliError::OperationFailed("Unexpected response".to_string()));
        }
    }

    Ok(())
}

/// Enable the GPU
pub async fn enable() -> Result<(), CliError> {
    // Try daemon first
    match ipc::send_request(&Request::Enable).await {
        Ok(Response::Success { message }) => {
            log::info!("{}", message);
            return Ok(());
        }
        Ok(Response::Error { message }) => {
            return Err(CliError::OperationFailed(message));
        }
        Err(ipc::IpcError::DaemonNotRunning) => {
            // Daemon not running, do it directly
            gpu::enable()?;
            log::info!("GPU enabled");
            return Ok(());
        }
        Err(e) => return Err(e.into()),
        _ => return Err(CliError::OperationFailed("Unexpected response".to_string())),
    }
}

/// Disable the GPU
pub async fn disable(kill: bool, force: bool) -> Result<(), CliError> {
    // Try daemon first
    match ipc::send_request(&Request::Disable { kill, force }).await {
        Ok(Response::Success { message }) => {
            log::info!("{}", message);
            Ok(())
        }
        Ok(Response::Error { message }) => {
            Err(CliError::OperationFailed(message))
        }
        Ok(Response::ProcessesBlocking { processes }) => {
            eprintln!("Cannot disable GPU - processes are using it:");
            for proc in &processes {
                eprintln!("  {} (PID {})", proc.name, proc.pid);
            }
            eprintln!("\nUse --kill to terminate these processes, or --force to disable anyway.");
            Err(CliError::OperationFailed("Processes blocking".to_string()))
        }
        Ok(Response::Status { .. }) => {
            Err(CliError::OperationFailed("Unexpected response".to_string()))
        }
        Err(ipc::IpcError::DaemonNotRunning) => {
            // Daemon not running, do it directly
            match gpu::disable(kill, force) {
                Ok(()) => {
                    log::info!("GPU disabled");
                    Ok(())
                }
                Err(gpu::GpuError::ProcessesBlocking(processes)) => {
                    eprintln!("Cannot disable GPU - processes are using it:");
                    for proc in &processes {
                        eprintln!("  {} (PID {})", proc.name, proc.pid);
                    }
                    eprintln!("\nUse --kill to terminate these processes, or --force to disable anyway.");
                    Err(CliError::OperationFailed("Processes blocking".to_string()))
                }
                Err(e) => Err(e.into()),
            }
        }
        Err(e) => Err(e.into()),
    }
}
