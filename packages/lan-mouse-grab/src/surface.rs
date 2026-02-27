use input_event::{Event, KeyboardEvent, PointerEvent};
use std::collections::{HashSet, VecDeque};
use std::io::{ErrorKind, Write};
use std::os::fd::AsFd;
use std::os::unix::io::AsRawFd;
use wayland_client::backend::WaylandError;
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{
    wl_buffer, wl_compositor, wl_keyboard, wl_pointer, wl_region, wl_registry, wl_seat, wl_shm,
    wl_shm_pool, wl_surface,
};
use wayland_client::{
    delegate_noop, Connection, Dispatch, DispatchError, EventQueue, QueueHandle, WEnum,
};
use wayland_protocols::wp::keyboard_shortcuts_inhibit::zv1::client::{
    zwp_keyboard_shortcuts_inhibit_manager_v1::ZwpKeyboardShortcutsInhibitManagerV1,
    zwp_keyboard_shortcuts_inhibitor_v1::ZwpKeyboardShortcutsInhibitorV1,
};
use wayland_protocols::wp::pointer_constraints::zv1::client::{
    zwp_locked_pointer_v1::ZwpLockedPointerV1,
    zwp_pointer_constraints_v1::{Lifetime, ZwpPointerConstraintsV1},
};
use wayland_protocols::wp::relative_pointer::zv1::client::{
    zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1,
    zwp_relative_pointer_v1::{self, ZwpRelativePointerV1},
};
use wayland_protocols::wp::viewporter::client::{
    wp_viewport::WpViewport, wp_viewporter::WpViewporter,
};
use wayland_protocols_wlr::layer_shell::v1::client::{
    zwlr_layer_shell_v1::{Layer, ZwlrLayerShellV1},
    zwlr_layer_surface_v1::{self, Anchor, KeyboardInteractivity, ZwlrLayerSurfaceV1},
};

const KEY_LEFT_META: u32 = 125;
const KEY_RIGHT_META: u32 = 126;
const KEY_LEFT_META_XKB: u32 = 133;
const KEY_RIGHT_META_XKB: u32 = 134;
const KEY_HOME: u32 = 102;
const KEY_HOME_XKB: u32 = 110;

const FRAME_WIDTH: u32 = 1920;
const FRAME_HEIGHT: u32 = 1080;
const FRAME_STRIDE: u32 = FRAME_WIDTH * 4;
const FRAME_SIZE: usize = (FRAME_STRIDE * FRAME_HEIGHT) as usize;

pub enum CaptureMsg {
    Input(Event),
    Exit,
}

struct Globals {
    compositor: wl_compositor::WlCompositor,
    shm: wl_shm::WlShm,
    layer_shell: ZwlrLayerShellV1,
    seat: wl_seat::WlSeat,
    pointer_constraints: ZwpPointerConstraintsV1,
    relative_pointer_manager: ZwpRelativePointerManagerV1,
    shortcut_inhibit_manager: Option<ZwpKeyboardShortcutsInhibitManagerV1>,
    viewporter: WpViewporter,
}

struct ShmPool {
    pool: wl_shm_pool::WlShmPool,
    #[allow(dead_code)]
    file: std::fs::File,
    mmap: *mut u8,
    buffers: [wl_buffer::WlBuffer; 2],
    buffer_released: [bool; 2],
    current: usize,
}

impl ShmPool {
    fn new(shm: &wl_shm::WlShm, qh: &QueueHandle<State>) -> Self {
        let pool_size = FRAME_SIZE * 2;

        let file = tempfile::tempfile().expect("failed to create tempfile");
        file.set_len(pool_size as u64)
            .expect("failed to set file size");

        let mmap = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                pool_size,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                file.as_raw_fd(),
                0,
            ) as *mut u8
        };
        assert!(!mmap.is_null(), "mmap failed");

        let pool = shm.create_pool(file.as_fd(), pool_size as i32, qh, ());

        let buf0 = pool.create_buffer(
            0,
            FRAME_WIDTH as i32,
            FRAME_HEIGHT as i32,
            FRAME_STRIDE as i32,
            wl_shm::Format::Xrgb8888,
            qh,
            0usize,
        );
        let buf1 = pool.create_buffer(
            FRAME_SIZE as i32,
            FRAME_WIDTH as i32,
            FRAME_HEIGHT as i32,
            FRAME_STRIDE as i32,
            wl_shm::Format::Xrgb8888,
            qh,
            1usize,
        );

        Self {
            pool,
            file,
            mmap,
            buffers: [buf0, buf1],
            buffer_released: [true, true],
            current: 0,
        }
    }

    fn write_frame(&mut self, data: &[u8]) -> Option<&wl_buffer::WlBuffer> {
        let idx = self.current;
        if !self.buffer_released[idx] {
            let other = 1 - idx;
            if !self.buffer_released[other] {
                return None; // both busy
            }
            self.current = other;
            return self.write_frame(data);
        }

        let offset = idx * FRAME_SIZE;
        let dst = unsafe { std::slice::from_raw_parts_mut(self.mmap.add(offset), FRAME_SIZE) };
        let copy_len = data.len().min(FRAME_SIZE);
        dst[..copy_len].copy_from_slice(&data[..copy_len]);

        self.buffer_released[idx] = false;
        self.current = 1 - idx;
        Some(&self.buffers[idx])
    }

    fn release_buffer(&mut self, idx: usize) {
        if idx < 2 {
            self.buffer_released[idx] = true;
        }
    }
}

impl Drop for ShmPool {
    fn drop(&mut self) {
        let pool_size = FRAME_SIZE * 2;
        unsafe {
            libc::munmap(self.mmap as *mut libc::c_void, pool_size);
        }
        for buf in &self.buffers {
            buf.destroy();
        }
        self.pool.destroy();
    }
}

pub struct State {
    globals: Globals,
    pointer: Option<wl_pointer::WlPointer>,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    pointer_lock: Option<ZwpLockedPointerV1>,
    rel_pointer: Option<ZwpRelativePointerV1>,
    shortcut_inhibitor: Option<ZwpKeyboardShortcutsInhibitorV1>,
    surface: Option<wl_surface::WlSurface>,
    layer_surface: Option<ZwlrLayerSurfaceV1>,
    viewport: Option<WpViewport>,
    initial_buffer: Option<wl_buffer::WlBuffer>,
    shm_pool: Option<ShmPool>,
    grabbed: bool,
    pressed_keys: HashSet<u32>,
    pub pending: VecDeque<CaptureMsg>,
    qh: QueueHandle<Self>,
    configured: bool,
    surface_width: u32,
    surface_height: u32,
    scroll_discrete_pending: bool,
}

impl State {
    fn create_initial_buffer(&self) -> wl_buffer::WlBuffer {
        let mut file = tempfile::tempfile().expect("tempfile");
        let size = FRAME_SIZE as u64;
        file.set_len(size).expect("set_len");

        // Fill full frame with dark gray so mapped surface is visibly present
        // even before first captured frame arrives.
        let row = vec![0x22u8, 0x22, 0x22, 0x00]; // XRGB8888 -> dark gray
        let mut line = Vec::with_capacity(FRAME_STRIDE as usize);
        for _ in 0..FRAME_WIDTH {
            line.extend_from_slice(&row);
        }
        for _ in 0..FRAME_HEIGHT {
            file.write_all(&line).expect("write line");
        }

        let pool = self
            .globals
            .shm
            .create_pool(file.as_fd(), FRAME_SIZE as i32, &self.qh, ());
        let buffer = pool.create_buffer(
            0,
            FRAME_WIDTH as i32,
            FRAME_HEIGHT as i32,
            FRAME_STRIDE as i32,
            wl_shm::Format::Xrgb8888,
            &self.qh,
            usize::MAX,
        );
        pool.destroy();
        buffer
    }

    fn create_window(&mut self) {
        let surface = self.globals.compositor.create_surface(&self.qh, ());
        let layer_surface = self.globals.layer_shell.get_layer_surface(
            &surface,
            None,
            Layer::Overlay,
            "lan-mouse-grab".into(),
            &self.qh,
            (),
        );

        let anchor = Anchor::Left | Anchor::Right | Anchor::Top | Anchor::Bottom;
        layer_surface.set_anchor(anchor);
        layer_surface.set_size(0, 0);
        layer_surface.set_exclusive_zone(-1);
        layer_surface.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
        surface.commit();

        let viewport = self.globals.viewporter.get_viewport(&surface, &self.qh, ());

        self.surface = Some(surface);
        self.layer_surface = Some(layer_surface);
        self.viewport = Some(viewport);
    }

    fn grab(&mut self) {
        if self.grabbed {
            return;
        }

        let (surface, pointer) = match (&self.surface, &self.pointer) {
            (Some(s), Some(p)) => (s.clone(), p.clone()),
            _ => return,
        };

        self.grabbed = true;

        if self.pointer_lock.is_none() {
            self.pointer_lock = Some(self.globals.pointer_constraints.lock_pointer(
                &surface,
                &pointer,
                None,
                Lifetime::Persistent,
                &self.qh,
                (),
            ));
        }

        if self.rel_pointer.is_none() {
            self.rel_pointer = Some(self.globals.relative_pointer_manager.get_relative_pointer(
                &pointer,
                &self.qh,
                (),
            ));
        }

        if let Some(mgr) = &self.globals.shortcut_inhibit_manager {
            if self.shortcut_inhibitor.is_none() {
                self.shortcut_inhibitor =
                    Some(mgr.inhibit_shortcuts(&surface, &self.globals.seat, &self.qh, ()));
            }
        }
    }

    fn check_exit_combo(&self) -> bool {
        let meta_down = self.pressed_keys.contains(&KEY_LEFT_META)
            || self.pressed_keys.contains(&KEY_RIGHT_META)
            || self.pressed_keys.contains(&KEY_LEFT_META_XKB)
            || self.pressed_keys.contains(&KEY_RIGHT_META_XKB);
        let home_down =
            self.pressed_keys.contains(&KEY_HOME) || self.pressed_keys.contains(&KEY_HOME_XKB);
        meta_down && home_down
    }

    pub fn submit_video_frame(&mut self, data: &[u8]) {
        let surface = match &self.surface {
            Some(s) => s.clone(),
            None => return,
        };

        if !self.configured {
            return;
        }

        if self.shm_pool.is_none() {
            self.shm_pool = Some(ShmPool::new(&self.globals.shm, &self.qh));
        }

        let pool = self.shm_pool.as_mut().unwrap();
        if let Some(buffer) = pool.write_frame(data) {
            surface.attach(Some(buffer), 0, 0);

            if let Some(viewport) = &self.viewport {
                viewport.set_source(0.0, 0.0, FRAME_WIDTH as f64, FRAME_HEIGHT as f64);
                viewport.set_destination(self.surface_width as i32, self.surface_height as i32);
            }

            surface.damage_buffer(0, 0, FRAME_WIDTH as i32, FRAME_HEIGHT as i32);
            surface.commit();
        }
    }
}

pub struct WaylandCapture {
    pub state: State,
    queue: EventQueue<State>,
}

impl WaylandCapture {
    pub fn new() -> anyhow::Result<Self> {
        let conn = Connection::connect_to_env()?;
        let (global_list, mut queue) = registry_queue_init::<State>(&conn)?;
        let qh = queue.handle();

        let compositor: wl_compositor::WlCompositor = global_list.bind(&qh, 4..=6, ())?;
        let shm: wl_shm::WlShm = global_list.bind(&qh, 1..=1, ())?;
        let layer_shell: ZwlrLayerShellV1 = global_list.bind(&qh, 3..=4, ())?;
        let seat: wl_seat::WlSeat = global_list.bind(&qh, 7..=9, ())?;
        let pointer_constraints: ZwpPointerConstraintsV1 = global_list.bind(&qh, 1..=1, ())?;
        let relative_pointer_manager: ZwpRelativePointerManagerV1 =
            global_list.bind(&qh, 1..=1, ())?;
        let shortcut_inhibit_manager: Option<ZwpKeyboardShortcutsInhibitManagerV1> =
            global_list.bind(&qh, 1..=1, ()).ok();
        let viewporter: WpViewporter = global_list.bind(&qh, 1..=1, ())?;

        let mut state = State {
            globals: Globals {
                compositor,
                shm,
                layer_shell,
                seat,
                pointer_constraints,
                relative_pointer_manager,
                shortcut_inhibit_manager,
                viewporter,
            },
            pointer: None,
            keyboard: None,
            pointer_lock: None,
            rel_pointer: None,
            shortcut_inhibitor: None,
            surface: None,
            layer_surface: None,
            viewport: None,
            initial_buffer: None,
            shm_pool: None,
            grabbed: false,
            pressed_keys: HashSet::new(),
            pending: VecDeque::new(),
            qh,
            configured: false,
            surface_width: FRAME_WIDTH,
            surface_height: FRAME_HEIGHT,
            scroll_discrete_pending: false,
        };

        state.create_window();
        queue.roundtrip(&mut state)?;

        Ok(WaylandCapture { state, queue })
    }

    pub fn flush_and_dispatch(&mut self) -> anyhow::Result<()> {
        self.queue.flush()?;

        if let Err(e) = self.queue.dispatch_pending(&mut self.state) {
            match e {
                DispatchError::Backend(WaylandError::Io(ref io))
                    if io.kind() == ErrorKind::WouldBlock => {}
                other => return Err(other.into()),
            }
        }

        // Truly non-blocking read: poll fd with zero timeout first.
        let mut pollfd = libc::pollfd {
            fd: self.queue.as_fd().as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let ready = unsafe { libc::poll(&mut pollfd, 1, 0) };
        if ready > 0 && (pollfd.revents & libc::POLLIN) != 0 {
            if let Some(guard) = self.queue.prepare_read() {
                match guard.read() {
                    Ok(_) => {}
                    Err(WaylandError::Io(ref e)) if e.kind() == ErrorKind::WouldBlock => {}
                    Err(e) => return Err(e.into()),
                }
            }
        }

        self.queue.dispatch_pending(&mut self.state)?;
        Ok(())
    }

    pub fn wayland_fd(&self) -> std::os::unix::io::RawFd {
        self.queue.as_fd().as_raw_fd()
    }
}

// Dispatch implementations

impl Dispatch<wl_seat::WlSeat, ()> for State {
    fn event(
        state: &mut Self,
        seat: &wl_seat::WlSeat,
        event: wl_seat::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_seat::Event::Capabilities {
            capabilities: WEnum::Value(caps),
        } = event
        {
            if caps.contains(wl_seat::Capability::Pointer) {
                if let Some(p) = state.pointer.take() {
                    p.release();
                }
                state.pointer = Some(seat.get_pointer(qh, ()));
            }
            if caps.contains(wl_seat::Capability::Keyboard) {
                if let Some(k) = state.keyboard.take() {
                    k.release();
                }
                state.keyboard = Some(seat.get_keyboard(qh, ()));
            }
        }
    }
}

impl Dispatch<wl_pointer::WlPointer, ()> for State {
    fn event(
        state: &mut Self,
        pointer: &wl_pointer::WlPointer,
        event: wl_pointer::Event,
        _: &(),
        _: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_pointer::Event::Enter {
                serial, surface, ..
            } => {
                let is_ours = state
                    .surface
                    .as_ref()
                    .map(|s| *s == surface)
                    .unwrap_or(false);
                if is_ours {
                    pointer.set_cursor(serial, None, 0, 0);
                    state.grab();
                }
            }
            wl_pointer::Event::Leave { .. } => {
                if let Some(lock) = state.pointer_lock.take() {
                    lock.destroy();
                }
                if let Some(rel) = state.rel_pointer.take() {
                    rel.destroy();
                }
                if let Some(inh) = state.shortcut_inhibitor.take() {
                    inh.destroy();
                }
                state.grabbed = false;
            }
            wl_pointer::Event::Button {
                time,
                button,
                state: btn_state,
                ..
            } => {
                state
                    .pending
                    .push_back(CaptureMsg::Input(Event::Pointer(PointerEvent::Button {
                        time,
                        button,
                        state: u32::from(btn_state),
                    })));
            }
            wl_pointer::Event::Axis { time, axis, value } => {
                if state.scroll_discrete_pending {
                    state.scroll_discrete_pending = false;
                } else {
                    state.pending.push_back(CaptureMsg::Input(Event::Pointer(
                        PointerEvent::Axis {
                            time,
                            axis: u32::from(axis) as u8,
                            value,
                        },
                    )));
                }
            }
            wl_pointer::Event::AxisValue120 { axis, value120 } => {
                state.scroll_discrete_pending = true;
                state.pending.push_back(CaptureMsg::Input(Event::Pointer(
                    PointerEvent::AxisDiscrete120 {
                        axis: u32::from(axis) as u8,
                        value: value120,
                    },
                )));
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_keyboard::WlKeyboard, ()> for State {
    fn event(
        state: &mut Self,
        _: &wl_keyboard::WlKeyboard,
        event: wl_keyboard::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            wl_keyboard::Event::Key {
                time,
                key,
                state: key_state,
                ..
            } => {
                let pressed = u32::from(key_state) != 0;
                if pressed {
                    state.pressed_keys.insert(key);
                } else {
                    state.pressed_keys.remove(&key);
                }

                if state.check_exit_combo() {
                    state.pending.push_back(CaptureMsg::Exit);
                    return;
                }

                state
                    .pending
                    .push_back(CaptureMsg::Input(Event::Keyboard(KeyboardEvent::Key {
                        time,
                        key,
                        state: u32::from(key_state) as u8,
                    })));
            }
            wl_keyboard::Event::Modifiers {
                mods_depressed,
                mods_latched,
                mods_locked,
                group,
                ..
            } => {
                state.pending.push_back(CaptureMsg::Input(Event::Keyboard(
                    KeyboardEvent::Modifiers {
                        depressed: mods_depressed,
                        latched: mods_latched,
                        locked: mods_locked,
                        group,
                    },
                )));
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwpRelativePointerV1, ()> for State {
    fn event(
        state: &mut Self,
        _: &ZwpRelativePointerV1,
        event: zwp_relative_pointer_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let zwp_relative_pointer_v1::Event::RelativeMotion {
            utime_hi,
            utime_lo,
            dx_unaccel: dx,
            dy_unaccel: dy,
            ..
        } = event
        {
            let time = ((((utime_hi as u64) << 32) | utime_lo as u64) / 1000) as u32;
            state
                .pending
                .push_back(CaptureMsg::Input(Event::Pointer(PointerEvent::Motion {
                    time,
                    dx,
                    dy,
                })));
        }
    }
}

impl Dispatch<ZwlrLayerSurfaceV1, ()> for State {
    fn event(
        state: &mut Self,
        layer_surface: &ZwlrLayerSurfaceV1,
        event: zwlr_layer_surface_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let zwlr_layer_surface_v1::Event::Configure {
            serial,
            width,
            height,
        } = event
        {
            layer_surface.ack_configure(serial);
            state.configured = true;
            state.surface_width = if width == 0 { FRAME_WIDTH } else { width };
            state.surface_height = if height == 0 { FRAME_HEIGHT } else { height };
            log::info!("layer surface configured");

            if let Some(surface) = &state.surface {
                if state.initial_buffer.is_none() {
                    let buffer = state.create_initial_buffer();
                    surface.attach(Some(&buffer), 0, 0);

                    if let Some(viewport) = &state.viewport {
                        viewport.set_source(0.0, 0.0, FRAME_WIDTH as f64, FRAME_HEIGHT as f64);
                        viewport.set_destination(
                            state.surface_width as i32,
                            state.surface_height as i32,
                        );
                    }

                    surface.damage_buffer(0, 0, FRAME_WIDTH as i32, FRAME_HEIGHT as i32);
                    surface.commit();
                    state.initial_buffer = Some(buffer);
                }
            }
        }
    }
}

impl Dispatch<wl_buffer::WlBuffer, usize> for State {
    fn event(
        state: &mut Self,
        _: &wl_buffer::WlBuffer,
        event: wl_buffer::Event,
        idx: &usize,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let wl_buffer::Event::Release = event {
            if *idx < 2 {
                if let Some(pool) = &mut state.shm_pool {
                    pool.release_buffer(*idx);
                }
            }
        }
    }
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(
        _: &mut Self,
        _: &wl_registry::WlRegistry,
        _: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

delegate_noop!(State: wl_region::WlRegion);
delegate_noop!(State: wl_shm_pool::WlShmPool);
delegate_noop!(State: wl_compositor::WlCompositor);
delegate_noop!(State: ZwlrLayerShellV1);
delegate_noop!(State: ZwpRelativePointerManagerV1);
delegate_noop!(State: ZwpKeyboardShortcutsInhibitManagerV1);
delegate_noop!(State: ZwpPointerConstraintsV1);
delegate_noop!(State: WpViewporter);
delegate_noop!(State: ignore wl_shm::WlShm);
delegate_noop!(State: ignore wl_surface::WlSurface);
delegate_noop!(State: ignore WpViewport);
delegate_noop!(State: ignore ZwpKeyboardShortcutsInhibitorV1);
delegate_noop!(State: ignore ZwpLockedPointerV1);
