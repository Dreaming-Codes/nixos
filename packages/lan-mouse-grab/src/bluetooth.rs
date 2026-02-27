use anyhow::{Context, Result};
use bluer::{
    adv::{Advertisement, Type},
    agent::Agent,
    gatt::local::{
        Application, Characteristic, CharacteristicNotify, CharacteristicNotifyMethod,
        CharacteristicNotifier, CharacteristicRead, CharacteristicWrite,
        CharacteristicWriteMethod, Descriptor, DescriptorRead, Service,
    },
    Address,
};
use futures::FutureExt;
use input_event::{Event, KeyboardEvent, PointerEvent};
use std::{collections::BTreeSet, fs, sync::Arc};
use tokio::sync::{mpsc, Mutex};
use uuid::Uuid;

const HID_SERVICE: u16 = 0x1812;
const HID_INFORMATION: u16 = 0x2A4A;
const HID_REPORT_MAP: u16 = 0x2A4B;
const HID_CONTROL_POINT: u16 = 0x2A4C;
const HID_REPORT: u16 = 0x2A4D;
const HID_PROTOCOL_MODE: u16 = 0x2A4E;
const HID_BOOT_KEYBOARD_INPUT_REPORT: u16 = 0x2A22;
const HID_BOOT_MOUSE_INPUT_REPORT: u16 = 0x2A33;
const REPORT_REFERENCE_DESC: u16 = 0x2908;

const REPORT_TYPE_INPUT: u8 = 0x01;
const REPORT_ID_KEYBOARD: u8 = 0x01;
const REPORT_ID_MOUSE: u8 = 0x02;

fn ble_uuid(short: u16) -> Uuid {
    Uuid::parse_str(&format!("0000{short:04x}-0000-1000-8000-00805f9b34fb")).unwrap()
}

const HID_REPORT_MAP_DATA: &[u8] = &[
    // Keyboard (Report ID 1)
    0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x85, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15,
    0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
    0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0xFF, 0x05, 0x07, 0x19, 0x00, 0x29, 0xFF, 0x81,
    0x00, 0xC0,
    // Mouse (Report ID 2)
    0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x85, 0x02, 0x09, 0x01, 0xA1, 0x00, 0x05, 0x09, 0x19,
    0x01, 0x29, 0x05, 0x15, 0x00, 0x25, 0x01, 0x95, 0x05, 0x75, 0x01, 0x81, 0x02, 0x95, 0x01,
    0x75, 0x03, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38, 0x15, 0x81, 0x25,
    0x7F, 0x75, 0x08, 0x95, 0x03, 0x81, 0x06, 0xC0, 0xC0,
];

fn evdev_to_hid(evdev: u32) -> u8 {
    match evdev {
        1 => 0x29,
        2 => 0x1E,
        3 => 0x1F,
        4 => 0x20,
        5 => 0x21,
        6 => 0x22,
        7 => 0x23,
        8 => 0x24,
        9 => 0x25,
        10 => 0x26,
        11 => 0x27,
        12 => 0x2D,
        13 => 0x2E,
        14 => 0x2A,
        15 => 0x2B,
        16 => 0x14,
        17 => 0x1A,
        18 => 0x08,
        19 => 0x15,
        20 => 0x17,
        21 => 0x1C,
        22 => 0x18,
        23 => 0x0C,
        24 => 0x12,
        25 => 0x13,
        26 => 0x2F,
        27 => 0x30,
        28 => 0x28,
        29 => 0xE0,
        30 => 0x04,
        31 => 0x16,
        32 => 0x07,
        33 => 0x09,
        34 => 0x0A,
        35 => 0x0B,
        36 => 0x0D,
        37 => 0x0E,
        38 => 0x0F,
        39 => 0x33,
        40 => 0x34,
        41 => 0x35,
        42 => 0xE1,
        43 => 0x31,
        44 => 0x1D,
        45 => 0x1B,
        46 => 0x06,
        47 => 0x19,
        48 => 0x05,
        49 => 0x11,
        50 => 0x10,
        51 => 0x36,
        52 => 0x37,
        53 => 0x38,
        54 => 0xE5,
        55 => 0x55,
        56 => 0xE2,
        57 => 0x2C,
        58 => 0x39,
        59 => 0x3A,
        60 => 0x3B,
        61 => 0x3C,
        62 => 0x3D,
        63 => 0x3E,
        64 => 0x3F,
        65 => 0x40,
        66 => 0x41,
        67 => 0x42,
        68 => 0x43,
        69 => 0x53,
        70 => 0x47,
        71 => 0x5F,
        72 => 0x60,
        73 => 0x61,
        74 => 0x56,
        75 => 0x5C,
        76 => 0x5D,
        77 => 0x5E,
        78 => 0x57,
        79 => 0x59,
        80 => 0x5A,
        81 => 0x5B,
        82 => 0x62,
        83 => 0x63,
        86 => 0x64,
        87 => 0x44,
        88 => 0x45,
        96 => 0x58,
        97 => 0xE4,
        98 => 0x54,
        99 => 0x46,
        100 => 0xE6,
        102 => 0x4A,
        103 => 0x52,
        104 => 0x4B,
        105 => 0x50,
        106 => 0x4F,
        107 => 0x4D,
        108 => 0x51,
        109 => 0x4E,
        110 => 0x49,
        111 => 0x4C,
        119 => 0x48,
        125 => 0xE3,
        126 => 0xE7,
        127 => 0x65,
        _ => 0x00,
    }
}

fn is_modifier(evdev: u32) -> Option<u8> {
    match evdev {
        29 => Some(0x01),
        42 => Some(0x02),
        56 => Some(0x04),
        125 => Some(0x08),
        97 => Some(0x10),
        54 => Some(0x20),
        100 => Some(0x40),
        126 => Some(0x80),
        _ => None,
    }
}

fn report_reference_descriptor(report_id: u8, report_type: u8) -> Descriptor {
    Descriptor {
        uuid: ble_uuid(REPORT_REFERENCE_DESC),
        read: Some(DescriptorRead {
            read: true,
            fun: Box::new(move |_req| async move { Ok(vec![report_id, report_type]) }.boxed()),
            ..Default::default()
        }),
        ..Default::default()
    }
}

struct HidState {
    modifiers: u8,
    pressed_keys: Vec<u8>,
    buttons: u8,
}

impl HidState {
    fn new() -> Self {
        Self {
            modifiers: 0,
            pressed_keys: Vec::new(),
            buttons: 0,
        }
    }

    // BLE HOGP: Report ID is NOT included in the payload.
    // The host knows the ID from the Report Reference descriptor.
    fn keyboard_report(&self) -> Vec<u8> {
        let mut pkt = vec![0u8; 8];
        pkt[0] = self.modifiers;
        // pkt[1] = reserved
        for (i, &key) in self.pressed_keys.iter().take(6).enumerate() {
            pkt[2 + i] = key;
        }
        pkt
    }

    fn mouse_report(&self, dx: i8, dy: i8, wheel: i8) -> Vec<u8> {
        vec![self.buttons, dx as u8, dy as u8, wheel as u8]
    }

    fn keyboard_boot_report(&self) -> Vec<u8> {
        let mut pkt = vec![0u8; 8];
        pkt[0] = self.modifiers;
        for (i, &key) in self.pressed_keys.iter().take(6).enumerate() {
            pkt[2 + i] = key;
        }
        pkt
    }

    fn mouse_boot_report(&self, dx: i8, dy: i8) -> Vec<u8> {
        vec![self.buttons, dx as u8, dy as u8]
    }

    fn handle_key(&mut self, key: u32, state: u8) {
        if let Some(mod_bit) = is_modifier(key) {
            if state != 0 {
                self.modifiers |= mod_bit;
            } else {
                self.modifiers &= !mod_bit;
            }
            return;
        }

        let hid = evdev_to_hid(key);
        if hid == 0 {
            return;
        }
        if state != 0 {
            if !self.pressed_keys.contains(&hid) {
                self.pressed_keys.push(hid);
            }
        } else {
            self.pressed_keys.retain(|&k| k != hid);
        }
    }

    fn handle_button(&mut self, button: u32, state: u32) {
        let bit = match button {
            0x110 => 0x01,
            0x111 => 0x02,
            0x112 => 0x04,
            0x113 => 0x08,
            0x114 => 0x10,
            _ => return,
        };
        if state != 0 {
            self.buttons |= bit;
        } else {
            self.buttons &= !bit;
        }
    }
}

pub struct BleHid {
    event_rx: mpsc::UnboundedReceiver<Event>,
    state: HidState,
}

fn tune_ble_connection_interval(adapter: &str) {
    let base = format!("/sys/kernel/debug/bluetooth/{adapter}");
    // 6 = 7.5ms, 9 = 11.25ms (units of 1.25ms)
    for (param, val) in [("conn_min_interval", "6"), ("conn_max_interval", "9")] {
        let path = format!("{base}/{param}");
        match fs::write(&path, val) {
            Ok(()) => log::info!("BLE HID: set {param}={val}"),
            Err(e) => log::warn!("BLE HID: failed to set {param}: {e} (need root for debugfs)"),
        }
    }
}

async fn trust_device(session: &bluer::Session, adapter_name: &str, addr: Address) {
    match session.adapter(adapter_name).and_then(|a| a.device(addr)) {
        Ok(device) => {
            if let Err(e) = device.set_trusted(true).await {
                log::warn!("BLE HID: failed to trust {addr}: {e}");
            }
        }
        Err(e) => log::warn!("BLE HID: failed to resolve device {addr}: {e}"),
    }
}

impl BleHid {
    pub fn new() -> (Self, mpsc::UnboundedSender<Event>) {
        let (tx, rx) = mpsc::unbounded_channel();
        (
            Self {
                event_rx: rx,
                state: HidState::new(),
            },
            tx,
        )
    }

    pub async fn run(mut self) -> Result<()> {
        let session = bluer::Session::new()
            .await
            .context("failed to connect to BlueZ D-Bus")?;

        let agent_confirm_session = session.clone();
        let agent_auth_session = session.clone();
        let agent_service_session = session.clone();
        let agent = Agent {
            request_default: true,
            request_confirmation: Some(Box::new(move |req| {
                let session = agent_confirm_session.clone();
                async move {
                    log::info!(
                        "BLE HID: request_confirmation {} from {} on {} -> accepted",
                        req.passkey,
                        req.device,
                        req.adapter
                    );
                    trust_device(&session, &req.adapter, req.device).await;
                    Ok(())
                }
                .boxed()
            })),
            request_authorization: Some(Box::new(move |req| {
                let session = agent_auth_session.clone();
                async move {
                    log::info!(
                        "BLE HID: request_authorization from {} on {} -> accepted",
                        req.device,
                        req.adapter
                    );
                    trust_device(&session, &req.adapter, req.device).await;
                    Ok(())
                }
                .boxed()
            })),
            authorize_service: Some(Box::new(move |req| {
                let session = agent_service_session.clone();
                async move {
                    log::info!(
                        "BLE HID: authorize_service {} from {} on {} -> accepted",
                        req.service,
                        req.device,
                        req.adapter
                    );
                    trust_device(&session, &req.adapter, req.device).await;
                    Ok(())
                }
                .boxed()
            })),
            ..Default::default()
        };
        let _agent_handle = session
            .register_agent(agent)
            .await
            .context("failed to register pairing agent")?;

        let adapter = session
            .default_adapter()
            .await
            .context("no Bluetooth adapter found")?;
        adapter
            .set_powered(true)
            .await
            .context("failed to power on adapter")?;
        adapter
            .set_pairable(true)
            .await
            .context("failed to set adapter pairable")?;
        adapter.set_pairable_timeout(0).await?;
        adapter
            .set_discoverable(true)
            .await
            .context("failed to set adapter discoverable")?;
        adapter.set_discoverable_timeout(0).await?;

        let addr = adapter.address().await?;
        tune_ble_connection_interval(adapter.name());
        log::info!("BLE HID: advertising on adapter {} ({addr})", adapter.name());

        let kb_value = Arc::new(Mutex::new(vec![0u8; 8]));
        let mouse_value = Arc::new(Mutex::new(vec![0u8; 4]));
        let kb_notifier: Arc<Mutex<Option<CharacteristicNotifier>>> = Arc::new(Mutex::new(None));
        let mouse_notifier: Arc<Mutex<Option<CharacteristicNotifier>>> = Arc::new(Mutex::new(None));
        let kb_boot_notifier: Arc<Mutex<Option<CharacteristicNotifier>>> = Arc::new(Mutex::new(None));
        let mouse_boot_notifier: Arc<Mutex<Option<CharacteristicNotifier>>> =
            Arc::new(Mutex::new(None));

        let kb_value_read_boot = kb_value.clone();
        let kb_value_read_report = kb_value.clone();
        let kb_notify_handle = kb_notifier.clone();
        let mouse_value_read_boot = mouse_value.clone();
        let mouse_value_read_report = mouse_value.clone();
        let mouse_notify_handle = mouse_notifier.clone();
        let kb_boot_notify_handle = kb_boot_notifier.clone();
        let mouse_boot_notify_handle = mouse_boot_notifier.clone();

        let app = Application {
            services: vec![Service {
                uuid: ble_uuid(HID_SERVICE),
                primary: true,
                characteristics: vec![
                    Characteristic {
                        uuid: ble_uuid(HID_PROTOCOL_MODE),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(|_req| async { Ok(vec![0x01]) }.boxed()),
                            ..Default::default()
                        }),
                        write: Some(CharacteristicWrite {
                            write_without_response: true,
                            method: CharacteristicWriteMethod::Fun(Box::new(|value, _req| {
                                async move {
                                    log::info!("BLE HID: protocol mode write: {value:?}");
                                    Ok(())
                                }
                                .boxed()
                            })),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_BOOT_KEYBOARD_INPUT_REPORT),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(move |_req| {
                                let v = kb_value_read_boot.clone();
                                async move {
                                    // Boot and report-mode keyboard layouts are identical (no report ID in either)
                                    let report = v.lock().await;
                                    Ok(report.clone())
                                }
                                .boxed()
                            }),
                            ..Default::default()
                        }),
                        notify: Some(CharacteristicNotify {
                            notify: true,
                            method: CharacteristicNotifyMethod::Fun(Box::new(move |notifier| {
                                let handle = kb_boot_notify_handle.clone();
                                async move {
                                    log::info!("BLE HID: keyboard boot notify session started");
                                    *handle.lock().await = Some(notifier);
                                }
                                .boxed()
                            })),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_BOOT_MOUSE_INPUT_REPORT),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(move |_req| {
                                let v = mouse_value_read_boot.clone();
                                async move {
                                    // Boot mouse: buttons, dx, dy (no wheel, no report ID)
                                    let report = v.lock().await;
                                    Ok(vec![report[0], report[1], report[2]])
                                }
                                .boxed()
                            }),
                            ..Default::default()
                        }),
                        notify: Some(CharacteristicNotify {
                            notify: true,
                            method: CharacteristicNotifyMethod::Fun(Box::new(move |notifier| {
                                let handle = mouse_boot_notify_handle.clone();
                                async move {
                                    log::info!("BLE HID: mouse boot notify session started");
                                    *handle.lock().await = Some(notifier);
                                }
                                .boxed()
                            })),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_INFORMATION),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(|_req| async { Ok(vec![0x11, 0x01, 0x00, 0x02]) }.boxed()),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_REPORT_MAP),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(|_req| async { Ok(HID_REPORT_MAP_DATA.to_vec()) }.boxed()),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_CONTROL_POINT),
                        write: Some(CharacteristicWrite {
                            write_without_response: true,
                            method: CharacteristicWriteMethod::Fun(Box::new(|value, _req| {
                                async move {
                                    log::info!("BLE HID: control point write: {value:?}");
                                    Ok(())
                                }
                                .boxed()
                            })),
                            ..Default::default()
                        }),
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_REPORT),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(move |_req| {
                                let v = kb_value_read_report.clone();
                                async move { Ok(v.lock().await.clone()) }.boxed()
                            }),
                            ..Default::default()
                        }),
                        notify: Some(CharacteristicNotify {
                            notify: true,
                            method: CharacteristicNotifyMethod::Fun(Box::new(move |notifier| {
                                let handle = kb_notify_handle.clone();
                                async move {
                                    log::info!("BLE HID: keyboard notify session started");
                                    *handle.lock().await = Some(notifier);
                                }
                                .boxed()
                            })),
                            ..Default::default()
                        }),
                        descriptors: vec![report_reference_descriptor(
                            REPORT_ID_KEYBOARD,
                            REPORT_TYPE_INPUT,
                        )],
                        ..Default::default()
                    },
                    Characteristic {
                        uuid: ble_uuid(HID_REPORT),
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(move |_req| {
                                let v = mouse_value_read_report.clone();
                                async move { Ok(v.lock().await.clone()) }.boxed()
                            }),
                            ..Default::default()
                        }),
                        notify: Some(CharacteristicNotify {
                            notify: true,
                            method: CharacteristicNotifyMethod::Fun(Box::new(move |notifier| {
                                let handle = mouse_notify_handle.clone();
                                async move {
                                    log::info!("BLE HID: mouse notify session started");
                                    *handle.lock().await = Some(notifier);
                                }
                                .boxed()
                            })),
                            ..Default::default()
                        }),
                        descriptors: vec![report_reference_descriptor(
                            REPORT_ID_MOUSE,
                            REPORT_TYPE_INPUT,
                        )],
                        ..Default::default()
                    },
                ],
                ..Default::default()
            }],
            ..Default::default()
        };

        let _app_handle = adapter
            .serve_gatt_application(app)
            .await
            .context("failed to register GATT application")?;
        log::info!("BLE HID: GATT application registered, advertising...");

        let service_uuids: BTreeSet<Uuid> = [ble_uuid(HID_SERVICE)].into_iter().collect();
        let adv = Advertisement {
            advertisement_type: Type::Peripheral,
            service_uuids,
            discoverable: Some(true),
            local_name: Some("LanMouseGrab".to_string()),
            appearance: Some(0x03C1),
            ..Default::default()
        };
        let _adv_handle = adapter.advertise(adv).await?;

        // Event loop with motion coalescing: drain all pending events,
        // accumulate mouse deltas, then send one merged notification per batch.
        loop {
            let first = self.event_rx.recv().await;
            if first.is_none() {
                break;
            }

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
                        if axis == 0 {
                            acc_wheel += value as i32;
                            mouse_moved = true;
                        }
                    }
                    Event::Pointer(PointerEvent::AxisDiscrete120 { axis, value }) => {
                        if axis == 0 {
                            acc_wheel -= value / 120;
                            mouse_moved = true;
                        }
                    }
                }
            }

            if kb_changed {
                let report = self.state.keyboard_report();
                let boot_report = self.state.keyboard_boot_report();
                *kb_value.lock().await = report.clone();
                if let Some(n) = kb_notifier.lock().await.as_mut() {
                    if let Err(e) = n.notify(report).await {
                        log::warn!("BLE HID: keyboard notify error: {e}");
                        *kb_notifier.lock().await = None;
                    }
                }
                if let Some(n) = kb_boot_notifier.lock().await.as_mut() {
                    if let Err(e) = n.notify(boot_report).await {
                        log::warn!("BLE HID: keyboard boot notify error: {e}");
                        *kb_boot_notifier.lock().await = None;
                    }
                }
            }

            if mouse_moved || btn_changed {
                let dx = (acc_dx as i8).clamp(-127, 127);
                let dy = (acc_dy as i8).clamp(-127, 127);
                let wh = (acc_wheel as i8).clamp(-127, 127);
                let report = self.state.mouse_report(dx, dy, wh);
                let boot_report = self.state.mouse_boot_report(dx, dy);
                *mouse_value.lock().await = report.clone();
                if let Some(n) = mouse_notifier.lock().await.as_mut() {
                    if let Err(e) = n.notify(report).await {
                        log::warn!("BLE HID: mouse notify error: {e}");
                        *mouse_notifier.lock().await = None;
                    }
                }
                if let Some(n) = mouse_boot_notifier.lock().await.as_mut() {
                    if let Err(e) = n.notify(boot_report).await {
                        log::warn!("BLE HID: mouse boot notify error: {e}");
                        *mouse_boot_notifier.lock().await = None;
                    }
                }
            }
        }

        Ok(())
    }
}
