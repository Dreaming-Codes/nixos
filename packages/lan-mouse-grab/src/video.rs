use anyhow::{bail, Context, Result};
use gstreamer::prelude::*;
use gstreamer_video::prelude::*;

pub struct VideoPipeline {
    pipeline: gstreamer::Pipeline,
    appsink: gstreamer_app::AppSink,
}

pub fn detect_capture_card() -> Result<String> {
    gstreamer::init().context("failed to init GStreamer")?;

    let output = std::process::Command::new("v4l2-ctl")
        .arg("--list-devices")
        .output()
        .context("failed to execute v4l2-ctl --list-devices")?;

    let output_str = String::from_utf8_lossy(&output.stdout);

    for line in output_str.lines() {
        let line = line.trim();
        if !line.starts_with("/dev/video") {
            continue;
        }
        let device = line;

        let format_output = std::process::Command::new("v4l2-ctl")
            .args(["-d", device, "--list-formats-ext"])
            .output();

        if let Ok(fmt_out) = format_output {
            let fmt_str = String::from_utf8_lossy(&fmt_out.stdout);
            if fmt_str.contains("MJPG")
                && fmt_str.contains("1920x1080")
                && fmt_str.contains("60.000 fps")
            {
                log::info!("detected capture card at {device}");
                return Ok(device.to_string());
            }
        }
    }

    bail!("no capture card detected (need MJPEG 1920x1080@60fps)")
}

fn select_decoder() -> String {
    if let Ok(force) = std::env::var("LAN_MOUSE_GRAB_DECODER") {
        let force = force.trim().to_string();
        if !force.is_empty() {
            if gstreamer::ElementFactory::find(&force).is_some() {
                log::info!("using forced JPEG decoder: {force}");
                return force;
            }
            log::warn!("forced decoder '{force}' not found; falling back");
        }
    }

    // Default to hardware decoder. Set LAN_MOUSE_GRAB_HW_DECODER=0 to force software.
    if std::env::var("LAN_MOUSE_GRAB_HW_DECODER").ok().as_deref() == Some("0") {
        log::info!("using JPEG decoder: jpegdec (software mode)");
        return "jpegdec".to_string();
    }

    let candidates = [
        "jpegdec",
        "nvjpegdec",
        "vajpegdec",
        "vaapijpegdec",
        "v4l2jpegdec",
    ];
    for name in candidates {
        if gstreamer::ElementFactory::find(name).is_some() {
            log::info!("using JPEG decoder: {name}");
            return name.to_string();
        }
    }
    log::warn!("no known JPEG decoder found, defaulting to jpegdec");
    "jpegdec".to_string()
}

impl VideoPipeline {
    pub fn new(device: &str) -> Result<Self> {
        gstreamer::init().context("failed to init GStreamer")?;

        let decoder = select_decoder();

        // Use the same tone-fix approach for both hardware decoders.
        let use_hw_tone_fix = (decoder == "nvjpegdec" || decoder == "vajpegdec")
            && std::env::var("LAN_MOUSE_GRAB_HW_TONE_FIX").ok().as_deref() != Some("0");
        let nv_brightness =
            std::env::var("LAN_MOUSE_GRAB_NV_BRIGHTNESS").unwrap_or_else(|_| "0.03".to_string());
        let nv_contrast =
            std::env::var("LAN_MOUSE_GRAB_NV_CONTRAST").unwrap_or_else(|_| "1.06".to_string());
        let nv_saturation =
            std::env::var("LAN_MOUSE_GRAB_NV_SATURATION").unwrap_or_else(|_| "1.02".to_string());

        let pipeline_str = if use_hw_tone_fix {
            log::info!(
                "hardware tone-fix path enabled for {decoder} (brightness={nv_brightness}, contrast={nv_contrast}, saturation={nv_saturation})"
            );
            format!(
                "v4l2src device={device} \
                 ! image/jpeg,width=1920,height=1080,framerate=60/1 \
                 ! {decoder} \
                 ! videoconvert \
                 ! video/x-raw,format=BGRx,colorimetry=1:1:0:0 \
                 ! videobalance brightness={nv_brightness} contrast={nv_contrast} saturation={nv_saturation} \
                 ! video/x-raw,format=BGRx,colorimetry=1:1:0:0 \
                 ! appsink name=sink sync=false async=false max-buffers=1 drop=true"
            )
        } else {
            format!(
                "v4l2src device={device} \
                 ! image/jpeg,width=1920,height=1080,framerate=60/1 \
                 ! {decoder} \
                 ! videoconvert \
                 ! video/x-raw,format=BGRx,colorimetry=1:1:0:0 \
                 ! appsink name=sink sync=false async=false max-buffers=1 drop=true"
            )
        };

        let pipeline = gstreamer::parse::launch(&pipeline_str)
            .context("failed to create GStreamer pipeline")?
            .downcast::<gstreamer::Pipeline>()
            .map_err(|_| anyhow::anyhow!("pipeline cast failed"))?;

        let appsink = pipeline
            .by_name("sink")
            .context("appsink element not found")?
            .downcast::<gstreamer_app::AppSink>()
            .map_err(|_| anyhow::anyhow!("appsink cast failed"))?;

        Ok(Self { pipeline, appsink })
    }

    pub fn start(&self) -> Result<()> {
        self.pipeline
            .set_state(gstreamer::State::Playing)
            .map_err(|e| anyhow::anyhow!("failed to start pipeline: {e:?}"))?;
        let state = self
            .pipeline
            .state(gstreamer::ClockTime::from_mseconds(300))
            .1;
        log::info!("pipeline state: {state:?}");
        Ok(())
    }

    pub fn stop(&self) {
        let _ = self.pipeline.set_state(gstreamer::State::Null);
    }

    pub fn appsink(&self) -> &gstreamer_app::AppSink {
        &self.appsink
    }

    pub fn bus(&self) -> Option<gstreamer::Bus> {
        self.pipeline.bus()
    }
}

pub struct VideoFrame {
    pub data: Vec<u8>,
}

pub fn pull_frame(appsink: &gstreamer_app::AppSink) -> Result<Option<VideoFrame>> {
    let sample = match appsink.try_pull_sample(gstreamer::ClockTime::from_mseconds(50)) {
        Some(s) => s,
        None => return Ok(None),
    };

    let caps = sample.caps().context("sample has no caps")?;
    let info = gstreamer_video::VideoInfo::from_caps(caps)
        .map_err(|_| anyhow::anyhow!("invalid video caps"))?;

    let buffer = sample.buffer().context("sample has no buffer")?;

    // SHM fallback: copy pixel data
    let frame = gstreamer_video::VideoFrameRef::from_buffer_ref_readable(buffer, &info)
        .map_err(|_| anyhow::anyhow!("failed to map video frame"))?;

    let _stride = frame.plane_stride()[0] as usize;
    let data = frame.plane_data(0).context("no plane data")?;

    Ok(Some(VideoFrame {
        data: data.to_vec(),
    }))
}
