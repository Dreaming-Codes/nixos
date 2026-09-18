//! Initrd helper: unlock cryptroot with FIDO2, or defer to passphrase cryptsetup.
//! Always exits 0 so systemd-cryptsetup@cryptroot can still run.
//!
//! Wait UI: Plymouth display-message + watch-keystroke (Enter), not ask-password.
//! Killing ask-password leaves Plymouth stuck on the old password prompt.
//! PIN UI: systemd-ask-password (fresh prompt after hide-message).

use std::path::Path;
use std::time::{Duration, Instant};

use smol::future;
use smol::process::{Command, Stdio};
use smol::{block_on, Async, Timer};
use udev::{EventType, MonitorBuilder};

const NAME: &str = "cryptroot";
const SRC: &str = "/dev/disk/by-partlabel/disk-main-root";
const FIDO_OPTS: &str = "fido2-device=auto,headless,discard,token-timeout=10";
const PIN_TRIES: u32 = 3;
const ATTACH_TIMEOUT: Duration = Duration::from_secs(60);
const YUBICO_VENDOR: &str = "1050";
const WAIT_MSG: &str = "Insert YubiKey, or press Enter for LUKS passphrase";

fn main() {
    if let Err(e) = block_on(run()) {
        eprintln!("cryptroot-fido-or-pass: {e}, deferring to passphrase");
    }
}

async fn run() -> Result<(), String> {
    wait_for_block(SRC, Duration::from_secs(30)).await?;
    if Mapper::is_open(NAME) {
        return Ok(());
    }
    ensure_tools()?;

    match Wait::for_fido_or_passphrase().await? {
        WaitEnd::AlreadyOpen | WaitEnd::Passphrase => return Ok(()),
        WaitEnd::Fido => {}
    }

    PinUnlock::run().await?;
    Ok(())
}

fn ensure_tools() -> Result<(), String> {
    for bin in ["/bin/systemd-ask-password", "/bin/systemd-cryptsetup"] {
        if !Path::new(bin).is_file() {
            return Err(format!("{bin} missing"));
        }
    }
    Ok(())
}

async fn wait_for_block(path: &str, budget: Duration) -> Result<(), String> {
    let start = Instant::now();
    while !Path::new(path).exists() {
        if start.elapsed() > budget {
            return Err(format!("{path} not found"));
        }
        Timer::after(Duration::from_millis(100)).await;
    }
    Ok(())
}

struct Mapper;

impl Mapper {
    fn is_open(name: &str) -> bool {
        Path::new(&format!("/dev/mapper/{name}")).exists()
    }
}

struct Plymouth;

impl Plymouth {
    fn running() -> bool {
        std::process::Command::new("/bin/plymouth")
            .arg("--ping")
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    async fn display_message(text: &str) {
        let _ = Command::new("/bin/plymouth")
            .args(["display-message", &format!("--text={text}")])
            .status()
            .await;
    }

    async fn hide_message(text: &str) {
        let _ = Command::new("/bin/plymouth")
            .args(["hide-message", &format!("--text={text}")])
            .status()
            .await;
        // Some themes keep password chrome until a no-op update.
        let _ = Command::new("/bin/plymouth")
            .args(["update", "--status= "])
            .status()
            .await;
    }

    /// Block until Enter (or Return). Used instead of ask-password for the wait UI.
    fn spawn_watch_enter() -> std::io::Result<smol::process::Child> {
        Command::new("/bin/plymouth")
            .args([
                "watch-keystroke",
                // CR and LF cover both Enter variants.
                "--keys=\n\r",
                "--command=/bin/true",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
    }
}

struct Fido;

impl Fido {
    fn device_is_yubico(dev: &udev::Device) -> bool {
        if let Some(v) = dev.attribute_value("idVendor") {
            if v.to_string_lossy() == YUBICO_VENDOR {
                return true;
            }
        }
        if let Some(v) = dev.property_value("ID_VENDOR_ID") {
            if v.to_string_lossy().eq_ignore_ascii_case(YUBICO_VENDOR) {
                return true;
            }
        }
        for key in ["ID_VENDOR_FROM_DATABASE", "HID_NAME", "ID_MODEL_FROM_DATABASE"] {
            if let Some(v) = dev.property_value(key) {
                if v.to_string_lossy().to_ascii_lowercase().contains("yubico") {
                    return true;
                }
            }
        }
        if let Some(parent) = dev.parent() {
            if Self::device_is_yubico(&parent) {
                return true;
            }
        }
        false
    }

    fn present() -> bool {
        for subsystem in ["usb", "hidraw"] {
            let Ok(mut enumerator) = udev::Enumerator::new() else {
                continue;
            };
            let _ = enumerator.match_subsystem(subsystem);
            let Ok(devices) = enumerator.scan_devices() else {
                continue;
            };
            if devices.into_iter().any(|d| Self::device_is_yubico(&d)) {
                return true;
            }
        }
        false
    }

    async fn attach(pin: &str) -> bool {
        let mut child = match Command::new("/bin/systemd-cryptsetup")
            .args(["attach", NAME, SRC, "-", FIDO_OPTS])
            .env("PIN", pin)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(_) => return false,
        };

        let id = child.id();
        match future::or(
            async { child.status().await.map(Some).unwrap_or(None) },
            async {
                Timer::after(ATTACH_TIMEOUT).await;
                unsafe {
                    libc::kill(id as libc::pid_t, libc::SIGTERM);
                }
                None
            },
        )
        .await
        {
            Some(status) => status.success(),
            None => {
                let _ = child.status().await;
                false
            }
        }
    }
}

struct Ask;

impl Ask {
    async fn ask_forever(prompt: &str) -> Option<String> {
        let output = Command::new("/bin/systemd-ask-password")
            .args(["--timeout=0", "-n", "--", prompt])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await
            .ok()?;
        if !output.status.success() {
            return None;
        }
        let mut out = String::from_utf8_lossy(&output.stdout).into_owned();
        while out.ends_with('\n') || out.ends_with('\r') {
            out.pop();
        }
        Some(out)
    }
}

enum WaitEnd {
    Fido,
    Passphrase,
    AlreadyOpen,
}

struct Wait;

impl Wait {
    async fn for_fido_or_passphrase() -> Result<WaitEnd, String> {
        if Mapper::is_open(NAME) {
            return Ok(WaitEnd::AlreadyOpen);
        }
        if Fido::present() {
            return Ok(WaitEnd::Fido);
        }

        let end = if Plymouth::running() {
            Self::wait_plymouth().await?
        } else {
            Self::wait_ask_password().await?
        };

        if Mapper::is_open(NAME) {
            return Ok(WaitEnd::AlreadyOpen);
        }
        if Fido::present() {
            return Ok(WaitEnd::Fido);
        }
        Ok(end)
    }

    /// Message (not password field) + Enter via watch-keystroke. Clearable on FIDO.
    async fn wait_plymouth() -> Result<WaitEnd, String> {
        Plymouth::display_message(WAIT_MSG).await;

        let mut watch = Plymouth::spawn_watch_enter()
            .map_err(|e| format!("plymouth watch-keystroke: {e}"))?;
        let watch_id = watch.id();

        let winner = future::or(
            async {
                Self::wait_yubico_udev().await;
                WaitEnd::Fido
            },
            async {
                let _ = watch.status().await;
                if Fido::present() {
                    WaitEnd::Fido
                } else {
                    WaitEnd::Passphrase
                }
            },
        )
        .await;

        unsafe {
            libc::kill(watch_id as libc::pid_t, libc::SIGTERM);
        }
        let _ = watch.status().await;
        Plymouth::hide_message(WAIT_MSG).await;
        // Brief yield so the theme drops the message before the PIN ask.
        Timer::after(Duration::from_millis(100)).await;

        Ok(winner)
    }

    /// Console fallback when Plymouth is not up.
    async fn wait_ask_password() -> Result<WaitEnd, String> {
        let mut ask = Command::new("/bin/systemd-ask-password")
            .args(["--timeout=0", "-n", "--", WAIT_MSG])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("ask-password: {e}"))?;
        let ask_id = ask.id();

        let winner = future::or(
            async {
                Self::wait_yubico_udev().await;
                WaitEnd::Fido
            },
            async {
                match ask.status().await {
                    Ok(st) if st.success() && !Fido::present() => WaitEnd::Passphrase,
                    _ if Fido::present() => WaitEnd::Fido,
                    _ => WaitEnd::Passphrase,
                }
            },
        )
        .await;

        unsafe {
            libc::kill(ask_id as libc::pid_t, libc::SIGTERM);
        }
        let _ = ask.status().await;
        Ok(winner)
    }

    async fn wait_yubico_udev() {
        let fallback = async {
            loop {
                if Fido::present() || Mapper::is_open(NAME) {
                    return;
                }
                Timer::after(Duration::from_millis(200)).await;
            }
        };

        let Ok(builder) = MonitorBuilder::new() else {
            fallback.await;
            return;
        };
        let Ok(builder) = builder
            .match_subsystem("usb")
            .and_then(|b| b.match_subsystem("hidraw"))
        else {
            fallback.await;
            return;
        };
        let Ok(socket) = builder.listen() else {
            fallback.await;
            return;
        };

        if Fido::present() {
            return;
        }

        let Ok(async_sock) = Async::new(socket) else {
            fallback.await;
            return;
        };

        loop {
            if Mapper::is_open(NAME) || Fido::present() {
                return;
            }
            if async_sock.readable().await.is_err() {
                Timer::after(Duration::from_millis(50)).await;
                continue;
            }
            for event in async_sock.get_ref().iter() {
                match event.event_type() {
                    EventType::Add | EventType::Bind | EventType::Change => {
                        if Fido::device_is_yubico(&event.device()) {
                            return;
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

struct PinUnlock;

impl PinUnlock {
    async fn run() -> Result<(), String> {
        for _ in 0..PIN_TRIES {
            if Mapper::is_open(NAME) {
                return Ok(());
            }
            if !Fido::present() {
                return Err("token removed".into());
            }

            match Ask::ask_forever("YubiKey PIN (Enter = LUKS passphrase)").await {
                None => return Err("passphrase selected".into()),
                Some(pin) if pin.is_empty() => return Err("passphrase selected".into()),
                Some(pin) => {
                    if Fido::attach(&pin).await {
                        return Ok(());
                    }
                    eprintln!("cryptroot-fido-or-pass: FIDO unlock failed, retrying");
                }
            }
        }
        Err("FIDO PIN not accepted".into())
    }
}
