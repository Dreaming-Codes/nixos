mod connection;
mod surface;
mod video;

use connection::{ConnectionEvent, ConnectionManager};
use lan_mouse_proto::ProtoEvent;
use surface::{CaptureMsg, WaylandCapture};
use std::process::Command;
use std::time::Duration;
use tokio::sync::mpsc;

const REMOTE_HOST: &str = "DreamingWinzoz.local";
const REMOTE_PORT: u16 = 4242;
const RECONNECT_DELAY: Duration = Duration::from_secs(3);
const RECONNECT_MAX_DELAY: Duration = Duration::from_secs(30);

fn notify(summary: &str, body: &str, urgency: &str) {
    let _ = Command::new("notify-send")
        .args(["-u", urgency, summary, body])
        .spawn();
}

fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    // Print and notify fingerprint on first run
    let fingerprint = connection::get_fingerprint()?;
    log::info!("certificate fingerprint: {fingerprint}");
    notify(
        "Capture Card",
        &format!("Fingerprint: {fingerprint}"),
        "normal",
    );

    // Detect capture card
    let device = match video::detect_capture_card() {
        Ok(dev) => dev,
        Err(e) => {
            notify("Capture Card", &format!("Error: {e}"), "critical");
            return Err(e);
        }
    };

    // Build the tokio runtime (single-threaded for wayland compat)
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;

    rt.block_on(async move { run(device).await })
}

async fn run(device: String) -> anyhow::Result<()> {
    // Create GStreamer pipeline
    let pipeline = video::VideoPipeline::new(&device)?;
    pipeline.start()?;
    log::info!("GStreamer pipeline started for {device}");

    // Create Wayland capture surface
    let mut capture = WaylandCapture::new()?;
    log::info!("wayland layer-shell surface created");

    // Set up connection manager with background retry
    let (conn_event_tx, mut conn_event_rx) = mpsc::unbounded_channel();
    let mut conn_mgr = ConnectionManager::new(conn_event_tx.clone());

    // Start initial connection attempt (non-blocking)
    let connect_result = conn_mgr.resolve_and_connect(REMOTE_HOST, REMOTE_PORT).await;
    if let Err(e) = &connect_result {
        log::warn!("initial connection failed: {e}, will retry in background");
        notify(
            "Capture Card",
            &format!("Connection to {REMOTE_HOST} failed, retrying..."),
            "normal",
        );
    }

    let gst_bus = pipeline.bus();
    let appsink = pipeline.appsink().clone();
    let wayland_fd = capture.wayland_fd();

    // Timer for reconnection attempts
    let mut reconnect_delay = RECONNECT_DELAY;
    let mut reconnect_timer: Option<tokio::time::Instant> = if !conn_mgr.is_connected() {
        Some(tokio::time::Instant::now() + reconnect_delay)
    } else {
        None
    };

    // Main event loop
    let mut poll_interval = tokio::time::interval(Duration::from_millis(1));
    poll_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        // Poll at ~1000Hz for low latency
        poll_interval.tick().await;

        // Check GStreamer bus for EOS/errors
        if let Some(bus) = &gst_bus {
            while let Some(msg) = bus.pop() {
                use gstreamer::MessageView;
                match msg.view() {
                    MessageView::Eos(..) => {
                        log::info!("capture card: end of stream");
                        notify("Capture Card", "Capture card disconnected", "critical");
                        conn_mgr.disconnect().await;
                        pipeline.stop();
                        std::process::exit(1);
                    }
                    MessageView::Error(err) => {
                        log::error!("GStreamer error: {:?}", err.error());
                        notify(
                            "Capture Card",
                            &format!("GStreamer error: {}", err.error()),
                            "critical",
                        );
                        conn_mgr.disconnect().await;
                        pipeline.stop();
                        std::process::exit(1);
                    }
                    _ => {}
                }
            }
        }

        // Pull video frames and render
        if let Ok(Some(frame)) = video::pull_frame(&appsink) {
            if frame.dma_buf_fd.is_some() {
                // TODO: DMA-BUF zero-copy path via zwp_linux_dmabuf_v1
                // For now, fall through to SHM if we somehow got a DMA-BUF
                // without SHM data (shouldn't happen with current pipeline)
                log::debug!("DMA-BUF frame received (zero-copy not yet implemented, using SHM)");
            }
            if !frame.data.is_empty() {
                capture.state.submit_video_frame(&frame.data);
            }
        }

        // Dispatch Wayland events
        capture.flush_and_dispatch()?;

        // Process Wayland input events
        while let Some(msg) = capture.state.pending.pop_front() {
            match msg {
                CaptureMsg::Exit => {
                    log::info!("exit combo pressed, shutting down");
                    conn_mgr.disconnect().await;
                    pipeline.stop();
                    return Ok(());
                }
                CaptureMsg::Input(event) => {
                    if conn_mgr.is_connected() {
                        let proto = ProtoEvent::Input(event);
                        if !conn_mgr.send(proto).await {
                            log::warn!("send failed, marking disconnected");
                            conn_mgr.disconnect().await;
                            reconnect_delay = RECONNECT_DELAY;
                            reconnect_timer =
                                Some(tokio::time::Instant::now() + reconnect_delay);
                        }
                    }
                }
            }
        }

        // Handle connection events
        while let Ok(event) = conn_event_rx.try_recv() {
            match event {
                ConnectionEvent::Connected => {
                    log::info!("connected to {REMOTE_HOST}");
                    notify("Capture Card", &format!("Connected to {REMOTE_HOST}"), "normal");
                    reconnect_timer = None;
                    reconnect_delay = RECONNECT_DELAY;
                }
                ConnectionEvent::Disconnected(reason) => {
                    log::warn!("disconnected: {reason}");
                    reconnect_timer = Some(tokio::time::Instant::now() + reconnect_delay);
                }
                ConnectionEvent::SendError(reason) => {
                    log::warn!("send error: {reason}");
                }
            }
        }

        // Reconnection logic
        if let Some(deadline) = reconnect_timer {
            if tokio::time::Instant::now() >= deadline {
                log::info!("attempting reconnection to {REMOTE_HOST}...");
                match conn_mgr.try_connect().await {
                    Ok(()) => {
                        reconnect_timer = None;
                        reconnect_delay = RECONNECT_DELAY;
                    }
                    Err(e) => {
                        log::warn!("reconnection failed: {e}");
                        reconnect_delay =
                            (reconnect_delay * 2).min(RECONNECT_MAX_DELAY);
                        reconnect_timer =
                            Some(tokio::time::Instant::now() + reconnect_delay);
                    }
                }
            }
        }
    }
}
