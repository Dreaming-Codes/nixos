//! Workaround for https://github.com/wwmm/easyeffects/issues/4878
//!
//! WirePlumber's autoswitch-bluetooth-profile only switches a bluez card to
//! HFP when an app records *directly* from the bluez source. EasyEffects
//! sits between apps and the bluez mic via virtual nodes
//! (`easyeffects_source` / `ee_sie_*` filters), and the autoswitch script
//! cannot traverse that path so the mic stays silent on A2DP.
//!
//! This watcher attaches to PipeWire and switches the relevant bluez card
//! to its highest-priority `headset-head-unit*` profile when:
//!   1. There is a Link from a `bluez_input.*` node to an `ee_sie_*` node
//!      (i.e. the user picked the bluez mic in EasyEffects' UI)
//!   2. There is a Link from `easyeffects_source` to a non-monitor
//!      `Stream/Input/Audio` node (i.e. some app actually wants the mic)
//!
//! When either becomes false, the previously saved profile is restored
//! after a short grace period to avoid flapping.

use std::collections::HashMap;
use std::io::Write;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use pipewire_native::{
    self as pipewire, closure,
    context::Context,
    core::CoreEvents,
    main_loop::MainLoop,
    properties::Properties,
    proxy::{
        device::{Device, DeviceEvents},
        registry::RegistryEvents,
    },
    some_closure, types,
};
use pipewire_native_spa as spa;

const RESTORE_GRACE: Duration = Duration::from_millis(1500);

#[derive(Debug, Clone)]
struct ProfileEntry {
    index: u32,
    name: String,
    priority: i32,
}

#[derive(Default)]
struct DeviceTrack {
    proxy: Option<Device>,
    name: String,
    profiles: Vec<ProfileEntry>,
    current: Option<String>,
}

#[derive(Default, Clone)]
struct NodeTrack {
    name: String,
    media_class: String,
    stream_monitor: bool,
    device_id: Option<u32>,
}

#[derive(Default, Clone, Copy)]
struct LinkTrack {
    output_node: u32,
    input_node: u32,
}

#[derive(Default)]
struct State {
    devices: HashMap<u32, DeviceTrack>,
    nodes: HashMap<u32, NodeTrack>,
    links: HashMap<u32, LinkTrack>,
    saved_profiles: HashMap<u32, String>,
    restore_pending_since: Option<Instant>,
}

fn log(msg: &str) {
    let mut e = std::io::stderr().lock();
    let _ = writeln!(e, "[ee-bluez-autoswitch] {}", msg);
}

fn parse_profile_pod(pod: &spa::pod::RawPodOwned) -> Option<ProfileEntry> {
    let mut parser = spa::pod::parser::Parser::new(pod.data());
    let (entry, _) = parser
        .pop_object_raw::<u32, _>(|object_parser, _object_type, _id| {
            let mut index: Option<u32> = None;
            let mut name: Option<String> = None;
            let mut priority: i32 = 0;
            for (key, _flags, raw_pod) in object_parser {
                // Profile keys: Index=1, Name=2, Priority=4
                match key {
                    1 => {
                        if let Ok(v) = raw_pod.decode::<i32>() {
                            index = Some(v as u32);
                        }
                    }
                    2 => {
                        if let Ok(v) = raw_pod.decode::<String>() {
                            name = Some(v);
                        }
                    }
                    4 => {
                        if let Ok(v) = raw_pod.decode::<i32>() {
                            priority = v;
                        }
                    }
                    _ => {}
                }
            }
            Ok::<_, spa::pod::Error>(match (index, name) {
                (Some(i), Some(n)) => Some(ProfileEntry {
                    index: i,
                    name: n,
                    priority,
                }),
                _ => None,
            })
        })
        .ok()?;
    entry
}

fn ee_input_routed_via_bluez(state: &State) -> Option<u32> {
    for link in state.links.values() {
        let out = state.nodes.get(&link.output_node);
        let inp = state.nodes.get(&link.input_node);
        if let (Some(o), Some(i)) = (out, inp) {
            if o.name.starts_with("bluez_input") && i.name.starts_with("ee_sie_") {
                if let Some(dev_id) = o.device_id {
                    return Some(dev_id);
                }
            }
        }
    }
    None
}

fn ee_has_active_capture_client(state: &State) -> bool {
    let ee_src_id = state
        .nodes
        .iter()
        .find(|(_, n)| n.name == "easyeffects_source")
        .map(|(id, _)| *id);
    let ee_src_id = match ee_src_id {
        Some(id) => id,
        None => return false,
    };
    for link in state.links.values() {
        if link.output_node != ee_src_id {
            continue;
        }
        if let Some(stream) = state.nodes.get(&link.input_node) {
            if stream.media_class == "Stream/Input/Audio" && !stream.stream_monitor {
                return true;
            }
        }
    }
    false
}

fn pick_headset_profile(profiles: &[ProfileEntry]) -> Option<&ProfileEntry> {
    profiles
        .iter()
        .filter(|p| p.name.starts_with("headset-head-unit"))
        .max_by_key(|p| p.priority)
}

/// Set the bluez card to a specific Profile by SPA index.
///
/// We bypass the pipewire-native Device::set_param path because in the
/// 0.1.4 release the marshalled pod is not accepted by the daemon for
/// the Profile param object (the call returns Ok but the daemon ignores
/// it). Shelling out to `pw-cli` is rock-solid and avoids re-implementing
/// the protocol marshalling.
fn set_device_profile(_device: &Device, bound_id: u32, index: u32) -> std::io::Result<()> {
    use std::process::{Command, Stdio};
    let arg = format!("{{ index: {} }}", index);
    let status = Command::new("pw-cli")
        .arg("set-param")
        .arg(bound_id.to_string())
        .arg("Profile")
        .arg(&arg)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("pw-cli set-param exited with {}", status),
        ))
    }
}

fn evaluate(state: &mut State) {
    let card_id = ee_input_routed_via_bluez(state);
    let has_client = ee_has_active_capture_client(state);
    let want_hfp = card_id.is_some() && has_client;

    if want_hfp {
        let card_id = card_id.unwrap();
        state.restore_pending_since = None;

        // If we already saved a profile for this card, we are mid-switch
        // (or the switch is already done), don't re-fire.
        if state.saved_profiles.contains_key(&card_id) {
            return;
        }

        let (current, target, proxy, dev_name) = {
            let dev = match state.devices.get(&card_id) {
                Some(d) => d,
                None => return,
            };
            let current = dev.current.clone().unwrap_or_default();
            if current.starts_with("headset-head-unit") {
                return;
            }
            let target = match pick_headset_profile(&dev.profiles) {
                Some(t) => t.clone(),
                None => return,
            };
            let proxy = match &dev.proxy {
                Some(p) => p.clone(),
                None => return,
            };
            (current, target, proxy, dev.name.clone())
        };

        log(&format!(
            "switching {} ({}) from '{}' to '{}' (index={})",
            dev_name, card_id, current, target.name, target.index
        ));
        if !current.is_empty() {
            state.saved_profiles.insert(card_id, current);
        }
        match set_device_profile(&proxy, card_id, target.index) {
            Ok(()) => {}
            Err(e) => log(&format!("set-param error: {}", e)),
        }
    } else if !state.saved_profiles.is_empty() && state.restore_pending_since.is_none() {
        state.restore_pending_since = Some(Instant::now());
    }
}

fn maybe_restore(state: &mut State) {
    let since = match state.restore_pending_since {
        Some(t) => t,
        None => return,
    };
    if since.elapsed() < RESTORE_GRACE {
        return;
    }

    let card_id = ee_input_routed_via_bluez(state);
    let has_client = ee_has_active_capture_client(state);
    if card_id.is_some() && has_client {
        state.restore_pending_since = None;
        return;
    }

    let saved = std::mem::take(&mut state.saved_profiles);
    state.restore_pending_since = None;

    for (dev_id, prev_name) in saved {
        let (proxy, target_index, dev_name) = match state.devices.get(&dev_id) {
            Some(d) => {
                let entry = d.profiles.iter().find(|p| p.name == prev_name);
                match (entry, &d.proxy) {
                    (Some(e), Some(p)) => (p.clone(), e.index, d.name.clone()),
                    _ => continue,
                }
            }
            None => continue,
        };
        log(&format!(
            "restoring {} ({}) to '{}' (index={})",
            dev_name, dev_id, prev_name, target_index
        ));
        match set_device_profile(&proxy, dev_id, target_index) {
            Ok(()) => {}
            Err(e) => log(&format!("restore set-param error: {}", e)),
        }
    }
}

fn main() -> std::io::Result<()> {
    pipewire::init();
    log("starting");

    let main_loop = MainLoop::new(&Properties::new()).expect("failed to create main loop");
    let context = Context::new(&main_loop, Properties::new())?;
    let core = context.connect(None)?;
    let registry = core.registry()?;

    // Quit cleanly on broken pipe (e.g. PipeWire restart)
    let main_loop_clone = main_loop.clone();
    let mut events = CoreEvents::default();
    events.error = some_closure!([main_loop_clone] _id, _seq, res, _msg, {
        if std::io::Error::from_raw_os_error(res as i32).kind()
            == std::io::ErrorKind::BrokenPipe
        {
            main_loop_clone.quit();
        }
    });
    core.add_listener(events);

    let state = Arc::new(Mutex::new(State::default()));

    {
        let registry_clone = registry.clone();
        let state_for_global = state.clone();
        registry.add_listener(RegistryEvents {
            global: some_closure!([registry_clone ^(state_for_global)] id, _perms, type_, version, props, {
                let id_val: u32 = id;

                if type_ == types::interface::DEVICE {
                    let api = props.get("device.api").unwrap_or("").to_string();
                    let name = props.get("device.name").unwrap_or("").to_string();
                    if api == "bluez5" {
                        if let Ok(object) = registry_clone.bind(id, type_, version) {
                            if let Some(dev) = object.downcast::<Device>() {
                                let dev_clone_for_listener = dev.clone();
                                let state_for_param = state_for_global.clone();
                                let mut events = DeviceEvents::default();
                                events.param = some_closure!([^(state_for_param)] _seq, param_id, _index, _next, pod, {
                                    let entry = parse_profile_pod(pod);
                                    let mut s = state_for_param.lock().unwrap();
                                    if let Some(track) = s.devices.get_mut(&id_val) {
                                        match param_id {
                                            spa::param::ParamType::Profile => {
                                                if let Some(p) = &entry {
                                                    log(&format!("device {} active profile is now '{}' (index={})", id_val, p.name, p.index));
                                                    track.current = Some(p.name.clone());
                                                }
                                            }
                                            spa::param::ParamType::EnumProfile => {
                                                if let Some(p) = entry {
                                                    track.profiles.retain(|x| x.index != p.index);
                                                    track.profiles.push(p);
                                                }
                                            }
                                            _ => {}
                                        }
                                    }
                                    evaluate(&mut s);
                                });
                                dev_clone_for_listener.add_listener(events);
                                let _ = dev_clone_for_listener.subscribe_params(&[
                                    spa::param::ParamType::Profile,
                                    spa::param::ParamType::EnumProfile,
                                ]);
                                let _ = dev_clone_for_listener.enum_params(
                                    0,
                                    Some(spa::param::ParamType::EnumProfile),
                                    0,
                                    u32::MAX,
                                    None,
                                );
                                let _ = dev_clone_for_listener.enum_params(
                                    0,
                                    Some(spa::param::ParamType::Profile),
                                    0,
                                    u32::MAX,
                                    None,
                                );

                                let mut s = state_for_global.lock().unwrap();
                                s.devices.insert(id_val, DeviceTrack {
                                    proxy: Some(dev_clone_for_listener),
                                    name,
                                    profiles: vec![],
                                    current: None,
                                });
                            }
                        }
                    }
                } else if type_ == types::interface::NODE {
                    let track = NodeTrack {
                        name: props.get("node.name").unwrap_or("").to_string(),
                        media_class: props.get("media.class").unwrap_or("").to_string(),
                        stream_monitor: props.get("stream.monitor").map(|s| s == "true").unwrap_or(false),
                        device_id: props.get("device.id").and_then(|s| s.parse::<u32>().ok()),
                    };
                    let mut s = state_for_global.lock().unwrap();
                    s.nodes.insert(id_val, track);
                    evaluate(&mut s);
                } else if type_ == types::interface::LINK {
                    let out_id = props.get("link.output.node").and_then(|s| s.parse::<u32>().ok());
                    let in_id = props.get("link.input.node").and_then(|s| s.parse::<u32>().ok());
                    if let (Some(o), Some(i)) = (out_id, in_id) {
                        let mut s = state_for_global.lock().unwrap();
                        s.links.insert(id_val, LinkTrack {
                            output_node: o,
                            input_node: i,
                        });
                        evaluate(&mut s);
                    }
                }
            }),
            global_remove: some_closure!([^(state_for_global)] id, {
                let id_val: u32 = id;
                let mut s = state_for_global.lock().unwrap();
                s.devices.remove(&id_val);
                s.nodes.remove(&id_val);
                s.links.remove(&id_val);
                s.saved_profiles.remove(&id_val);
                evaluate(&mut s);
            }),
        });
    }

    log("running");

    // Periodic timer to handle the debounced restore.
    let state_for_timer = state.clone();
    let mut timer_src = main_loop
        .add_timer(closure!([^(state_for_timer)] _expirations, {
            let mut s = state_for_timer.lock().unwrap();
            maybe_restore(&mut s);
        }))
        .expect("failed to create timer source");
    let interval = libc::timespec {
        tv_sec: 0,
        tv_nsec: 500_000_000,
    };
    main_loop
        .update_timer(&mut timer_src, &interval, Some(&interval), false)
        .expect("failed to arm timer");

    main_loop.run();
    Ok(())
}
