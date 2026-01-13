use serde::{Deserialize, Serialize};
use std::path::Path;
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

pub const SOCKET_PATH: &str = "/run/gpu-control/gpu-control.sock";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Request {
    Status,
    Enable,
    Disable { kill: bool, force: bool },
    /// User chose to keep GPU on from notification
    KeepOn,
    /// User chose to force disable from notification
    ForceDisable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Response {
    Status {
        #[serde(flatten)]
        status: crate::gpu::GpuStatus,
        daemon_state: Option<crate::state::GpuState>,
    },
    Success {
        message: String,
    },
    Error {
        message: String,
    },
    ProcessesBlocking {
        processes: Vec<crate::gpu::ProcessInfo>,
    },
}

#[derive(Error, Debug)]
pub enum IpcError {
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),
    #[error("Daemon not running")]
    DaemonNotRunning,
}

/// Client: Send a request to the daemon
pub async fn send_request(request: &Request) -> Result<Response, IpcError> {
    let socket_path = Path::new(SOCKET_PATH);
    if !socket_path.exists() {
        return Err(IpcError::DaemonNotRunning);
    }

    let mut stream = UnixStream::connect(socket_path).await?;
    let request_json = serde_json::to_string(request)?;

    stream.write_all(request_json.as_bytes()).await?;
    stream.write_all(b"\n").await?;
    stream.shutdown().await?;

    let mut reader = BufReader::new(stream);
    let mut response_line = String::new();
    reader.read_line(&mut response_line).await?;

    let response: Response = serde_json::from_str(&response_line)?;
    Ok(response)
}

/// Server: Create the socket listener
pub async fn create_listener() -> Result<UnixListener, IpcError> {
    let socket_path = Path::new(SOCKET_PATH);

    // Ensure parent directory exists
    if let Some(parent) = socket_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    // Remove existing socket
    if socket_path.exists() {
        tokio::fs::remove_file(socket_path).await?;
    }

    let listener = UnixListener::bind(socket_path)?;

    // Make socket accessible
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(socket_path, std::fs::Permissions::from_mode(0o666))?;
    }

    Ok(listener)
}

/// Server: Read a request from a connected client
pub async fn read_request(stream: &mut UnixStream) -> Result<Request, IpcError> {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).await?;
    let request: Request = serde_json::from_str(&line)?;
    Ok(request)
}

/// Server: Send a response to the client
pub async fn send_response(stream: &mut UnixStream, response: &Response) -> Result<(), IpcError> {
    let response_json = serde_json::to_string(response)?;
    stream.write_all(response_json.as_bytes()).await?;
    stream.write_all(b"\n").await?;
    Ok(())
}
