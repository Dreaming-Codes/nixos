mod connection;
mod surface;
mod video;

use std::process::Command;
use std::sync::mpsc;
use std::thread;

use input_event::Event;
use surface::{CaptureMsg, WaylandCapture};

const REMOTE_HOST: &str = "DreamingWinzoz.local";
const REMOTE_PORT: u16 = 4242;

fn notify(summary: &str, body: &str, urgency: &str) {
    let _ = Command::new("notify-send")
        .args(["-u", urgency, summary, body])
        .spawn();
}

fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    // Show fingerprint on startup
    match connection::get_fingerprint() {
        Ok(fp) => {
            log::info!("fingerprint: {fp}");
            notify("Capture Card", &format!("Fingerprint:\n{fp}"), "normal");
        }
        Err(e) => log::warn!("failed to get fingerprint: {e}"),
    }

    let device = match video::detect_capture_card() {
        Ok(dev) => dev,
        Err(e) => {
            notify("Capture Card", &format!("Error: {e}"), "critical");
            return Err(e);
        }
    };

    let pipeline = video::VideoPipeline::new(&device)?;
    pipeline.start()?;
    log::info!("GStreamer pipeline started for {device}");

    let mut capture = WaylandCapture::new()?;
    log::info!("wayland layer-shell surface created");

    // Channel for sending input events to the connection thread
    let (input_tx, input_rx) = mpsc::channel::<Event>();

    // Spawn DTLS connection in a background thread with its own tokio runtime
    let conn_handle = thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("failed to create tokio runtime");

        rt.block_on(async {
            connection_loop(input_rx).await;
        });
    });

    let gst_bus = pipeline.bus();
    let appsink = pipeline.appsink().clone();

    loop {
        // Check GStreamer bus for EOS/errors
        if let Some(bus) = &gst_bus {
            while let Some(msg) = bus.pop() {
                use gstreamer::MessageView;
                match msg.view() {
                    MessageView::Eos(..) => {
                        log::info!("capture card: end of stream");
                        notify("Capture Card", "Capture card disconnected", "critical");
                        pipeline.stop();
                        drop(input_tx);
                        let _ = conn_handle.join();
                        std::process::exit(1);
                    }
                    MessageView::Error(err) => {
                        log::error!("GStreamer error: {:?}", err.error());
                        notify(
                            "Capture Card",
                            &format!("GStreamer error: {}", err.error()),
                            "critical",
                        );
                        pipeline.stop();
                        drop(input_tx);
                        let _ = conn_handle.join();
                        std::process::exit(1);
                    }
                    _ => {}
                }
            }
        }

        // Pull video frames and render
        while let Ok(Some(frame)) = video::pull_frame(&appsink) {
            if !frame.data.is_empty() {
                capture.state.submit_video_frame(&frame.data);
            }
        }

        // Dispatch Wayland events
        capture.dispatch()?;

        // Process Wayland input events
        while let Some(msg) = capture.state.pending.pop_front() {
            match msg {
                CaptureMsg::Exit => {
                    log::info!("exit combo pressed, shutting down");
                    pipeline.stop();
                    drop(input_tx);
                    let _ = conn_handle.join();
                    return Ok(());
                }
                CaptureMsg::Input(event) => {
                    // Send to connection thread (non-blocking, drop if full)
                    let _ = input_tx.send(event);
                }
            }
        }
    }
}

async fn connection_loop(input_rx: mpsc::Receiver<Event>) {
    use connection::{ConnectionManager, ConnectionEvent};
    use lan_mouse_proto::ProtoEvent;
    use tokio::sync::mpsc as tokio_mpsc;

    let (event_tx, mut event_rx) = tokio_mpsc::unbounded_channel::<ConnectionEvent>();
    let mut mgr = ConnectionManager::new(event_tx);

    // Try connecting in background with retries
    let mut connected = false;
    let mut retry_delay = std::time::Duration::from_secs(1);
    const MAX_RETRY: std::time::Duration = std::time::Duration::from_secs(30);

    loop {
        // Try to connect if not connected
        if !connected {
            match mgr.resolve_and_connect(REMOTE_HOST, REMOTE_PORT).await {
                Ok(()) => {
                    connected = true;
                    retry_delay = std::time::Duration::from_secs(1);
                    log::info!("connected to {REMOTE_HOST}:{REMOTE_PORT}");
                }
                Err(e) => {
                    log::warn!("connection failed: {e}, retrying in {retry_delay:?}");
                    tokio::time::sleep(retry_delay).await;
                    retry_delay = (retry_delay * 2).min(MAX_RETRY);
                    continue;
                }
            }
        }

        // Drain connection events
        while let Ok(ev) = event_rx.try_recv() {
            match ev {
                ConnectionEvent::Connected => log::info!("connection event: connected"),
                ConnectionEvent::Disconnected(reason) => {
                    log::warn!("disconnected: {reason}");
                    connected = false;
                }
                ConnectionEvent::SendError(reason) => {
                    log::warn!("send error: {reason}");
                    connected = false;
                }
            }
        }

        // Forward input events from the main thread
        match input_rx.try_recv() {
            Ok(event) => {
                let proto = ProtoEvent::Input(event);
                if !mgr.send(proto).await {
                    connected = false;
                    log::warn!("failed to send input, will reconnect");
                }
            }
            Err(mpsc::TryRecvError::Empty) => {
                // No input events, yield briefly to avoid busy-spinning
                tokio::time::sleep(std::time::Duration::from_micros(500)).await;
            }
            Err(mpsc::TryRecvError::Disconnected) => {
                // Main thread exited, clean up
                log::info!("input channel closed, disconnecting");
                mgr.disconnect().await;
                return;
            }
        }
    }
}
