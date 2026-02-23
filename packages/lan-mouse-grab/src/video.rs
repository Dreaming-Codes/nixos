use anyhow::{bail, Context, Result};
use gstreamer::prelude::*;
use gstreamer_video::prelude::*;

pub struct VideoPipeline {
    pipeline: gstreamer::Pipeline,
    appsink: gstreamer_app::AppSink,
}

pub fn detect_capture_card() -> Result<String> {
    gstreamer::init().context("failed to init GStreamer")?;

    let monitor = gstreamer::DeviceMonitor::new();
    monitor.add_filter(Some("Video/Source"), None);
    monitor
        .start()
        .map_err(|_| anyhow::anyhow!("failed to start device monitor"))?;

    let devices = monitor.devices();
    monitor.stop();

    for device in &devices {
        let caps = device.caps().unwrap_or_else(gstreamer::Caps::new_empty);
        let name = device.display_name();
        let props = device.properties();

        let device_path = props
            .as_ref()
            .and_then(|p| p.get::<String>("device.path").ok())
            .or_else(|| {
                props
                    .as_ref()
                    .and_then(|p| p.get::<String>("object.path").ok())
            })
            .or_else(|| {
                props
                    .as_ref()
                    .and_then(|p| p.get::<String>("api.v4l2.path").ok())
            });

        log::debug!("found device: {name}, caps: {caps}, path: {device_path:?}");

        let has_mjpeg_1080p60 = (0..caps.size()).any(|i| {
            let s = caps.structure(i).unwrap();
            let is_jpeg = s.name().as_str() == "image/jpeg";
            let is_1080p = s.get::<i32>("width").ok() == Some(1920)
                && s.get::<i32>("height").ok() == Some(1080);
            let is_60fps = s
                .get::<gstreamer::Fraction>("framerate")
                .ok()
                .map(|f| f.numer() >= 60 && f.denom() == 1)
                .unwrap_or(false);
            is_jpeg && is_1080p && is_60fps
        });

        if has_mjpeg_1080p60 {
            if let Some(path) = device_path {
                log::info!("detected capture card: {name} at {path}");
                return Ok(path);
            }
        }
    }

    bail!("no capture card detected (need MJPEG 1920x1080@60fps)")
}

fn select_decoder() -> &'static str {
    let candidates = ["vaapijpegdec", "v4l2jpegdec", "jpegdec"];
    for name in candidates {
        if gstreamer::ElementFactory::find(name).is_some() {
            log::info!("using JPEG decoder: {name}");
            return name;
        }
    }
    log::warn!("no known JPEG decoder found, defaulting to jpegdec");
    "jpegdec"
}

impl VideoPipeline {
    pub fn new(device: &str) -> Result<Self> {
        gstreamer::init().context("failed to init GStreamer")?;

        let decoder = select_decoder();

        let pipeline_str = format!(
            "v4l2src device={device} \
             ! image/jpeg,width=1920,height=1080,framerate=60/1 \
             ! {decoder} \
             ! videoconvert \
             ! video/x-raw,format=BGRx \
             ! appsink name=sink sync=false max-buffers=1 drop=true"
        );

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
    pub width: u32,
    pub height: u32,
    pub stride: usize,
    pub dma_buf_fd: Option<std::os::unix::io::RawFd>,
}

pub fn pull_frame(appsink: &gstreamer_app::AppSink) -> Result<Option<VideoFrame>> {
    let sample = match appsink.try_pull_sample(gstreamer::ClockTime::ZERO) {
        Some(s) => s,
        None => return Ok(None),
    };

    let caps = sample.caps().context("sample has no caps")?;
    let info = gstreamer_video::VideoInfo::from_caps(caps)
        .map_err(|_| anyhow::anyhow!("invalid video caps"))?;

    let buffer = sample.buffer().context("sample has no buffer")?;

    // Try DMA-BUF path first
    if buffer.n_memory() > 0 {
        let mem = buffer.peek_memory(0);
        if let Some(dmabuf) = mem.downcast_memory_ref::<gstreamer_allocators::DmaBufMemory>() {
            return Ok(Some(VideoFrame {
                data: Vec::new(),
                width: info.width(),
                height: info.height(),
                stride: info.stride()[0] as usize,
                dma_buf_fd: Some(dmabuf.fd()),
            }));
        }
    }

    // SHM fallback: copy pixel data
    let frame = gstreamer_video::VideoFrameRef::from_buffer_ref_readable(buffer, &info)
        .map_err(|_| anyhow::anyhow!("failed to map video frame"))?;

    let stride = frame.plane_stride()[0] as usize;
    let data = frame.plane_data(0).context("no plane data")?;

    Ok(Some(VideoFrame {
        data: data.to_vec(),
        width: info.width(),
        height: info.height(),
        stride,
        dma_buf_fd: None,
    }))
}
