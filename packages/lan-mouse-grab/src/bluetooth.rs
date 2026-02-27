use anyhow::{Context, Result};
use bluer::{
    agent::Agent,
    l2cap::{SeqPacket, SeqPacketListener, SocketAddr},
    rfcomm::Profile,
    Address, AddressType,
};
use futures::{FutureExt, StreamExt};
use input_event::{Event, KeyboardEvent, PointerEvent};
use std::process::Command;
use tokio::sync::mpsc;

const PSM_HID_CTRL: u16 = 0x0011;
const PSM_HID_INTR: u16 = 0x0013;
const HIDP_HEADER_INPUT: u8 = 0xA1;

const SDP_RECORD: &str = r#"<?xml version="1.0" encoding="UTF-8" ?>
<record>
  <attribute id="0x0001">
    <sequence><uuid value="0x1124" /></sequence>
  </attribute>
  <attribute id="0x0004">
    <sequence>
      <sequence>
        <uuid value="0x0100" />
        <uint16 value="0x0011" />
      </sequence>
      <sequence>
        <uuid value="0x0011" />
      </sequence>
    </sequence>
  </attribute>
  <attribute id="0x0005">
    <sequence><uuid value="0x1002" /></sequence>
  </attribute>
  <attribute id="0x0006">
    <sequence>
      <uint16 value="0x656e" />
      <uint16 value="0x006a" />
      <uint16 value="0x0100" />
    </sequence>
  </attribute>
  <attribute id="0x0009">
    <sequence>
      <sequence>
        <uuid value="0x1124" />
        <uint16 value="0x0100" />
      </sequence>
    </sequence>
  </attribute>
  <attribute id="0x000d">
    <sequence>
      <sequence>
        <sequence>
          <uuid value="0x0100" />
          <uint16 value="0x0013" />
        </sequence>
        <sequence>
          <uuid value="0x0011" />
        </sequence>
      </sequence>
    </sequence>
  </attribute>
  <attribute id="0x0100"><text value="LanMouseGrab" /></attribute>
  <attribute id="0x0101"><text value="Virtual Keyboard+Mouse" /></attribute>
  <attribute id="0x0102"><text value="LanMouseGrab" /></attribute>
  <attribute id="0x0200"><uint16 value="0x0100" /></attribute>
  <attribute id="0x0201"><uint16 value="0x0111" /></attribute>
  <attribute id="0x0202"><uint8 value="0xc0" /></attribute>
  <attribute id="0x0203"><uint8 value="0x00" /></attribute>
  <attribute id="0x0204"><boolean value="false" /></attribute>
  <attribute id="0x0205"><boolean value="false" /></attribute>
  <attribute id="0x0206">
    <sequence>
      <sequence>
        <uint8 value="0x22" />
        <text encoding="hex" value="05010906a101850175019508050719e029e715002501810295017508810395057501050819012905910295017503910395067508150026ff000507190029ff8100c005010902a10185020901a100950575010509190129051500250181029501750381017508950305010930093109381581257f8106c0c0" />
      </sequence>
    </sequence>
  </attribute>
  <attribute id="0x0207">
    <sequence>
      <sequence>
        <uint16 value="0x0409" />
        <uint16 value="0x0100" />
      </sequence>
    </sequence>
  </attribute>
  <attribute id="0x020b"><uint16 value="0x0100" /></attribute>
  <attribute id="0x020c"><uint16 value="0x0c80" /></attribute>
  <attribute id="0x020d"><boolean value="false" /></attribute>
  <attribute id="0x020e"><boolean value="false" /></attribute>
  <attribute id="0x020f"><uint16 value="0x0640" /></attribute>
  <attribute id="0x0210"><uint16 value="0x0320" /></attribute>
</record>"#;

fn evdev_to_hid(evdev: u32) -> u8 {
    match evdev {
        1 => 0x29, 2 => 0x1E, 3 => 0x1F, 4 => 0x20, 5 => 0x21, 6 => 0x22, 7 => 0x23,
        8 => 0x24, 9 => 0x25, 10 => 0x26, 11 => 0x27, 12 => 0x2D, 13 => 0x2E, 14 => 0x2A,
        15 => 0x2B, 16 => 0x14, 17 => 0x1A, 18 => 0x08, 19 => 0x15, 20 => 0x17, 21 => 0x1C,
        22 => 0x18, 23 => 0x0C, 24 => 0x12, 25 => 0x13, 26 => 0x2F, 27 => 0x30, 28 => 0x28,
        29 => 0xE0, 30 => 0x04, 31 => 0x16, 32 => 0x07, 33 => 0x09, 34 => 0x0A, 35 => 0x0B,
        36 => 0x0D, 37 => 0x0E, 38 => 0x0F, 39 => 0x33, 40 => 0x34, 41 => 0x35, 42 => 0xE1,
        43 => 0x31, 44 => 0x1D, 45 => 0x1B, 46 => 0x06, 47 => 0x19, 48 => 0x05, 49 => 0x11,
        50 => 0x10, 51 => 0x36, 52 => 0x37, 53 => 0x38, 54 => 0xE5, 55 => 0x55, 56 => 0xE2,
        57 => 0x2C, 58 => 0x39, 59 => 0x3A, 60 => 0x3B, 61 => 0x3C, 62 => 0x3D, 63 => 0x3E,
        64 => 0x3F, 65 => 0x40, 66 => 0x41, 67 => 0x42, 68 => 0x43, 69 => 0x53, 70 => 0x47,
        71 => 0x5F, 72 => 0x60, 73 => 0x61, 74 => 0x56, 75 => 0x5C, 76 => 0x5D, 77 => 0x5E,
        78 => 0x57, 79 => 0x59, 80 => 0x5A, 81 => 0x5B, 82 => 0x62, 83 => 0x63, 86 => 0x64,
        87 => 0x44, 88 => 0x45, 96 => 0x58, 97 => 0xE4, 98 => 0x54, 99 => 0x46, 100 => 0xE6,
        102 => 0x4A, 103 => 0x52, 104 => 0x4B, 105 => 0x50, 106 => 0x4F, 107 => 0x4D,
        108 => 0x51, 109 => 0x4E, 110 => 0x49, 111 => 0x4C, 119 => 0x48, 125 => 0xE3,
        126 => 0xE7, 127 => 0x65,
        _ => 0x00,
    }
}

fn is_modifier(evdev: u32) -> Option<u8> {
    match evdev {
        29 => Some(0x01),  42 => Some(0x02),  56 => Some(0x04),  125 => Some(0x08),
        97 => Some(0x10),  54 => Some(0x20),  100 => Some(0x40), 126 => Some(0x80),
        _ => None,
    }
}

struct HidState {
    modifiers: u8,
    pressed_keys: Vec<u8>,
    buttons: u8,
}

impl HidState {
    fn new() -> Self {
        Self { modifiers: 0, pressed_keys: Vec::new(), buttons: 0 }
    }

    fn keyboard_report(&self) -> [u8; 10] {
        let mut pkt = [0u8; 10];
        pkt[0] = HIDP_HEADER_INPUT;
        pkt[1] = 0x01; // Report ID
        pkt[2] = self.modifiers;
        pkt[3] = 0x00; // reserved
        for (i, &key) in self.pressed_keys.iter().take(6).enumerate() {
            pkt[4 + i] = key;
        }
        pkt
    }

    fn mouse_report(&self, dx: i8, dy: i8, wheel: i8) -> [u8; 7] {
        [HIDP_HEADER_INPUT, 0x02, self.buttons, dx as u8, dy as u8, wheel as u8, 0x00]
    }

    fn handle_key(&mut self, key: u32, state: u8) {
        if let Some(mod_bit) = is_modifier(key) {
            if state != 0 { self.modifiers |= mod_bit; } else { self.modifiers &= !mod_bit; }
            return;
        }
        let hid = evdev_to_hid(key);
        if hid == 0 { return; }
        if state != 0 {
            if !self.pressed_keys.contains(&hid) { self.pressed_keys.push(hid); }
        } else {
            self.pressed_keys.retain(|&k| k != hid);
        }
    }

    fn handle_button(&mut self, button: u32, state: u32) {
        let bit = match button {
            0x110 => 0x01, 0x111 => 0x02, 0x112 => 0x04, 0x113 => 0x08, 0x114 => 0x10,
            _ => return,
        };
        if state != 0 { self.buttons |= bit; } else { self.buttons &= !bit; }
    }
}

async fn trust_device(session: &bluer::Session, adapter_name: &str, addr: Address) {
    match session.adapter(adapter_name).and_then(|a| a.device(addr)) {
        Ok(device) => {
            if let Err(e) = device.set_trusted(true).await {
                log::warn!("BT HID: failed to trust {addr}: {e}");
            }
        }
        Err(e) => log::warn!("BT HID: failed to resolve device {addr}: {e}"),
    }
}

pub struct BtHid {
    event_rx: mpsc::UnboundedReceiver<Event>,
    state: HidState,
}

impl BtHid {
    pub fn new() -> (Self, mpsc::UnboundedSender<Event>) {
        let (tx, rx) = mpsc::unbounded_channel();
        (Self { event_rx: rx, state: HidState::new() }, tx)
    }

    pub async fn run(mut self) -> Result<()> {
        let session = bluer::Session::new().await.context("failed to connect to BlueZ D-Bus")?;

        let agent_confirm = session.clone();
        let agent_auth = session.clone();
        let agent_svc = session.clone();
        let agent = Agent {
            request_default: true,
            request_confirmation: Some(Box::new(move |req| {
                let s = agent_confirm.clone();
                async move {
                    log::info!("BT HID: confirm {} from {} -> accepted", req.passkey, req.device);
                    trust_device(&s, &req.adapter, req.device).await;
                    Ok(())
                }.boxed()
            })),
            request_authorization: Some(Box::new(move |req| {
                let s = agent_auth.clone();
                async move {
                    log::info!("BT HID: authorize {} -> accepted", req.device);
                    trust_device(&s, &req.adapter, req.device).await;
                    Ok(())
                }.boxed()
            })),
            authorize_service: Some(Box::new(move |req| {
                let s = agent_svc.clone();
                async move {
                    log::info!("BT HID: authorize_service {} from {} -> accepted", req.service, req.device);
                    trust_device(&s, &req.adapter, req.device).await;
                    Ok(())
                }.boxed()
            })),
            ..Default::default()
        };
        let _agent_handle = session.register_agent(agent).await.context("failed to register agent")?;

        let adapter = session.default_adapter().await.context("no adapter")?;
        adapter.set_powered(true).await?;

        adapter.set_alias("LanMouseGrab".to_string()).await?;

        // Force CoD to Peripheral Keyboard+Pointing via raw HCI command.
        // We spawn a background task that keeps re-setting it every 2s
        // because PipeWire/BlueZ audio profiles reset it to Computer+Audio.
        tokio::spawn(async {
            loop {
                let _ = Command::new("hcitool")
                    .args(["cmd", "0x03", "0x0024", "0x40", "0x25", "0x00"])
                    .output();
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }
        });

        adapter.set_pairable(true).await?;
        adapter.set_pairable_timeout(0).await?;
        adapter.set_discoverable(true).await?;
        adapter.set_discoverable_timeout(0).await?;

        let addr = adapter.address().await?;
        log::info!("BT HID: adapter {} ({addr})", adapter.name());

        // Register SDP service record via BlueZ ProfileManager
        let profile = Profile {
            uuid: "00001124-0000-1000-8000-00805f9b34fb".parse()?,
            service_record: Some(SDP_RECORD.to_string()),
            role: Some(bluer::rfcomm::Role::Server),
            require_authentication: Some(true),
            require_authorization: Some(true),
            auto_connect: Some(true),
            ..Default::default()
        };
        let mut profile_handle = session.register_profile(profile).await
            .context("failed to register HID SDP profile (is the input plugin disabled?)")?;
        log::info!("BT HID: SDP service record registered");

        // Drain profile connection requests in background
        tokio::spawn(async move {
            while let Some(req) = profile_handle.next().await {
                log::debug!("BT HID: profile connect from {:?}", req.device());
                let _ = req.accept();
            }
        });

        // Bind L2CAP listeners
        let ctrl_listener = SeqPacketListener::bind(SocketAddr::new(
            Address::any(), AddressType::BrEdr, PSM_HID_CTRL,
        )).await.context("failed to bind L2CAP PSM 0x11 (control)")?;

        let intr_listener = SeqPacketListener::bind(SocketAddr::new(
            Address::any(), AddressType::BrEdr, PSM_HID_INTR,
        )).await.context("failed to bind L2CAP PSM 0x13 (interrupt)")?;

        log::info!("BT HID: listening on PSM 0x11 (ctrl) + 0x13 (intr)");

        loop {
            match self.accept_and_serve(&session, adapter.name(), &ctrl_listener, &intr_listener).await {
                Ok(()) => log::info!("BT HID: client disconnected"),
                Err(e) => {
                    log::warn!("BT HID: session error: {e:#}");
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                }
            }
            log::info!("BT HID: waiting for new connection...");
        }
    }

    async fn disconnect_audio_profiles(session: &bluer::Session, adapter_name: &str, addr: Address) {
        let audio_uuids: &[&str] = &[
            "0000110a-0000-1000-8000-00805f9b34fb", // A2DP Sink
            "0000110b-0000-1000-8000-00805f9b34fb", // A2DP Source
            "0000110c-0000-1000-8000-00805f9b34fb", // AVRCP Target
            "0000110d-0000-1000-8000-00805f9b34fb", // A2DP
            "0000110e-0000-1000-8000-00805f9b34fb", // AVRCP Controller
            "0000111e-0000-1000-8000-00805f9b34fb", // Handsfree
            "0000111f-0000-1000-8000-00805f9b34fb", // Handsfree AG
        ];
        if let Ok(adapter) = session.adapter(adapter_name) {
            if let Ok(device) = adapter.device(addr) {
                for uuid_str in audio_uuids {
                    if let Ok(uuid) = uuid_str.parse::<uuid::Uuid>() {
                        match device.disconnect_profile(&uuid).await {
                            Ok(()) => log::info!("BT HID: disconnected audio profile {uuid_str} from {addr}"),
                            Err(_) => {}
                        }
                    }
                }
            }
        }
    }

    async fn accept_and_serve(
        &mut self,
        session: &bluer::Session,
        adapter_name: &str,
        ctrl_listener: &SeqPacketListener,
        intr_listener: &SeqPacketListener,
    ) -> Result<()> {
        log::info!("BT HID: waiting for control channel...");
        let (_ctrl_sock, ctrl_sa) = ctrl_listener.accept().await.context("ctrl accept failed")?;
        let host_addr = ctrl_sa.addr;
        log::info!("BT HID: control channel connected from {host_addr}");

        // Disconnect audio profiles so Windows doesn't latch onto A2DP
        Self::disconnect_audio_profiles(session, adapter_name, host_addr).await;

        // Try to accept interrupt channel from host, with a timeout.
        // If host doesn't connect it, we initiate the connection ourselves.
        log::info!("BT HID: waiting for interrupt channel...");
        let intr_sock = tokio::select! {
            result = intr_listener.accept() => {
                let (sock, sa) = result.context("intr accept failed")?;
                log::info!("BT HID: interrupt channel accepted from {}", sa.addr);
                sock
            }
            _ = tokio::time::sleep(std::time::Duration::from_secs(5)) => {
                log::info!("BT HID: host didn't connect interrupt channel, connecting to {host_addr}...");
                let sock = SeqPacket::connect(SocketAddr::new(
                    host_addr, AddressType::BrEdr, PSM_HID_INTR,
                )).await.context("failed to connect interrupt channel to host")?;
                log::info!("BT HID: interrupt channel connected to {host_addr}");
                sock
            }
        };

        self.serve_input(intr_sock).await
    }

    async fn serve_input(&mut self, intr: SeqPacket) -> Result<()> {
        // Event loop with motion coalescing
        loop {
            let first = self.event_rx.recv().await;
            if first.is_none() { break; }

            let mut events = vec![first.unwrap()];
            while let Ok(ev) = self.event_rx.try_recv() {
                events.push(ev);
            }

            let mut acc_dx: f64 = 0.0;
            let mut acc_dy: f64 = 0.0;
            let mut acc_wheel: i32 = 0;
            let mut mouse_moved = false;
            let mut kb_changed = false;
            let mut btn_changed = false;

            for event in events {
                match event {
                    Event::Keyboard(KeyboardEvent::Key { key, state, .. }) => {
                        self.state.handle_key(key, state);
                        kb_changed = true;
                    }
                    Event::Keyboard(KeyboardEvent::Modifiers { .. }) => {}
                    Event::Pointer(PointerEvent::Motion { dx, dy, .. }) => {
                        acc_dx += dx;
                        acc_dy += dy;
                        mouse_moved = true;
                    }
                    Event::Pointer(PointerEvent::Button { button, state, .. }) => {
                        self.state.handle_button(button, state);
                        btn_changed = true;
                    }
                    Event::Pointer(PointerEvent::Axis { axis, value, .. }) => {
                        if axis == 0 { acc_wheel += value as i32; mouse_moved = true; }
                    }
                    Event::Pointer(PointerEvent::AxisDiscrete120 { axis, value }) => {
                        if axis == 0 { acc_wheel -= value / 120; mouse_moved = true; }
                    }
                }
            }

            if kb_changed {
                let report = self.state.keyboard_report();
                if let Err(e) = intr.send(&report).await {
                    log::warn!("BT HID: keyboard send error: {e}");
                    return Ok(());
                }
            }

            if mouse_moved || btn_changed {
                let dx = (acc_dx as i8).clamp(-127, 127);
                let dy = (acc_dy as i8).clamp(-127, 127);
                let wh = (acc_wheel as i8).clamp(-127, 127);
                let report = self.state.mouse_report(dx, dy, wh);
                if let Err(e) = intr.send(&report).await {
                    log::warn!("BT HID: mouse send error: {e}");
                    return Ok(());
                }
            }
        }
        Ok(())
    }
}
