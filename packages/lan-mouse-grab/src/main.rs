mod bluetooth;
mod surface;
mod video;

use std::process::Command;
use std::time::Duration;
use surface::{CaptureMsg, WaylandCapture};

fn notify(summary: &str, body: &str, urgency: &str) {
    let _ = Command::new("notify-send")
        .args(["-u", urgency, summary, body])
        .spawn();
}

fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let device = match video::detect_capture_card() {
        Ok(dev) => dev,
        Err(e) => {
            notify("Capture Card", &format!("Error: {e}"), "critical");
            return Err(e);
        }
    };

    // Multi-threaded runtime: Wayland+GStreamer on main, BT HID on thread pool.
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    rt.block_on(async move { run(device).await })
}

async fn run(device: String) -> anyhow::Result<()> {
    let pipeline = video::VideoPipeline::new(&device)?;
    pipeline.start()?;
    log::info!("GStreamer pipeline started for {device}");

    let mut capture = WaylandCapture::new()?;
    log::info!("wayland layer-shell surface created");

    // Spawn BLE HOGP backend
    let (ble_hid, input_tx) = bluetooth::BleHid::new();
    tokio::spawn(async move {
        if let Err(e) = ble_hid.run().await {
            log::error!("BLE HID error: {e:#}");
            notify("BLE HID", &format!("Bluetooth error: {e}"), "critical");
        }
    });

    let gst_bus = pipeline.bus();
    let appsink = pipeline.appsink().clone();
    let mut rendered_once = false;

    let mut poll_interval = tokio::time::interval(Duration::from_millis(1));
    poll_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        poll_interval.tick().await;

        if let Some(bus) = &gst_bus {
            while let Some(msg) = bus.pop() {
                use gstreamer::MessageView;
                match msg.view() {
                    MessageView::Eos(..) => {
                        log::info!("capture card: end of stream");
                        notify("Capture Card", "Capture card disconnected", "critical");
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
                        pipeline.stop();
                        std::process::exit(1);
                    }
                    _ => {}
                }
            }
        }

        if let Ok(Some(frame)) = video::pull_frame(&appsink) {
            if !frame.data.is_empty() {
                capture.state.submit_video_frame(&frame.data);
                if !rendered_once {
                    rendered_once = true;
                    log::info!("first video frame submitted");
                }
            }
        }

        capture.flush_and_dispatch()?;

        while let Some(msg) = capture.state.pending.pop_front() {
            match msg {
                CaptureMsg::Exit => {
                    log::info!("exit combo pressed, shutting down");
                    pipeline.stop();
                    std::process::exit(0);
                }
                CaptureMsg::Input(event) => {
                    let _ = input_tx.send(event);
                }
            }
        }
    }
}
