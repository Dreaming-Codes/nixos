{
  lib,
  config,
  pkgs,
  ...
}: let
  # Synaptics haptic trackpad on Precision 5690 (I2C HID).
  # Click strength is HID Feature report 0x37 (byte 0–100), not libinput.
  # If the pad freezes (enumerated but no reports), rebind manually via
  # trackpad-i2c-reset — no automatic rebind on boot/resume.
  trackpadDev = "i2c-VEN_06CB:00";
  trackpadDrv = "/sys/bus/i2c/drivers/i2c_hid_acpi";
  defaultIntensity = 100;

  rebindTrackpad = pkgs.writeShellScript "trackpad-i2c-rebind" ''
    set -euo pipefail
    DEV=${lib.escapeShellArg trackpadDev}
    DRV=${lib.escapeShellArg trackpadDrv}

    if [[ ! -e "/sys/bus/i2c/devices/$DEV" ]]; then
      echo "trackpad $DEV not present; skipping rebind"
      exit 0
    fi

    if [[ -e "$DRV/$DEV" ]]; then
      echo "$DEV" > "$DRV/unbind"
      sleep 0.6
    fi

    if [[ ! -e "$DRV/$DEV" ]]; then
      echo "$DEV" > "$DRV/bind"
    fi
  '';

  setHaptic = pkgs.writers.writeRustBin "set-trackpad-haptic-intensity" {
    rustcArgs = ["-O"];
  } ''
    use std::env;
    use std::fs;
    use std::io::{self, Write};
    use std::os::fd::AsRawFd;
    use std::path::PathBuf;
    use std::process;

    const DEFAULT_INTENSITY: u8 = ${toString defaultIntensity};
    const REPORT_ID: u8 = 0x37;
    const VID_PID: &str = "06CB:CFA0";
    const HID_ID_MARK: &str = "000006CB:0000CFA0";

    // HIDIOCSFEATURE(len) = _IOC(_IOC_WRITE|_IOC_READ, 'H', 0x06, len)
    fn hid_ioc_sfeature(len: u32) -> libc::c_ulong {
        const IOC_WRITE: u32 = 1;
        const IOC_READ: u32 = 2;
        let dir = IOC_WRITE | IOC_READ;
        let typ = b'H' as u32;
        let nr = 0x06u32;
        ((dir << 30) | (typ << 8) | nr | (len << 16)) as libc::c_ulong
    }

    mod libc {
        #![allow(non_camel_case_types)]
        pub type c_int = i32;
        pub type c_ulong = u64;
        extern "C" {
            pub fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
        }
    }

    fn find_hidraw() -> io::Result<PathBuf> {
        let class = PathBuf::from("/sys/class/hidraw");
        for entry in fs::read_dir(&class)? {
            let entry = entry?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if !name.starts_with("hidraw") {
                continue;
            }
            let uevent = entry.path().join("device/uevent");
            let Ok(text) = fs::read_to_string(&uevent) else {
                continue;
            };
            if text.contains(VID_PID) || text.contains(HID_ID_MARK) {
                return Ok(PathBuf::from(format!("/dev/{name}")));
            }
        }
        Err(io::Error::new(
            io::ErrorKind::NotFound,
            "no hidraw device for 06CB:CFA0",
        ))
    }

    fn set_intensity(path: &PathBuf, level: u8) -> io::Result<()> {
        let file = fs::OpenOptions::new().read(true).write(true).open(path)?;
        let mut buf = [REPORT_ID, level];
        let req = hid_ioc_sfeature(buf.len() as u32);
        let rc = unsafe { libc::ioctl(file.as_raw_fd(), req, buf.as_mut_ptr()) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    fn usage(prog: &str) {
        let _ = writeln!(
            io::stderr(),
            "Usage: {prog} [0-100]\n  Set Synaptics haptic click intensity (default {DEFAULT_INTENSITY})."
        );
    }

    fn main() {
        let mut args = env::args();
        let prog = args.next().unwrap_or_else(|| "set-trackpad-haptic-intensity".into());
        let level = match args.next() {
            None => DEFAULT_INTENSITY,
            Some(s) if s == "-h" || s == "--help" => {
                usage(&prog);
                process::exit(0);
            }
            Some(s) => match s.parse::<u8>() {
                Ok(n) if n <= 100 => n,
                _ => {
                    let _ = writeln!(io::stderr(), "intensity must be an integer 0–100");
                    usage(&prog);
                    process::exit(2);
                }
            },
        };
        if args.next().is_some() {
            usage(&prog);
            process::exit(2);
        }

        let path = match find_hidraw() {
            Ok(p) => p,
            Err(e) => {
                let _ = writeln!(io::stderr(), "{e}");
                process::exit(1);
            }
        };

        if let Err(e) = set_intensity(&path, level) {
            let _ = writeln!(
                io::stderr(),
                "failed to set intensity {level} on {}: {e}",
                path.display()
            );
            process::exit(1);
        }

        println!("set haptic intensity to {level} on {}", path.display());
    }
  '';

  setHapticBoot = pkgs.writeShellScript "trackpad-haptic-boot" ''
    set -euo pipefail
    for _ in $(seq 1 20); do
      if ${setHaptic}/bin/set-trackpad-haptic-intensity ${toString defaultIntensity}; then
        exit 0
      fi
      sleep 0.2
    done
    echo "warn: could not set haptic intensity (hidraw not ready)" >&2
    exit 0
  '';
in {
  imports = [./disk-config.nix];

  # Hardware report: hosts/x86_64-nixos/DreamingWorkDell/facter.json
  # (wired via flake-modules/hosts.nix). Regenerate with:
  #   sudo nixos-facter -o hosts/x86_64-nixos/DreamingWorkDell/facter.json
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.kernelModules = ["kvm-intel"];

  # Hybrid Intel Arc iGPU + NVIDIA RTX 5000 Ada (see modules/hardware/optimus.nix).
  # Bus IDs from lspci: 00:02.0 Intel, 01:00.0 NVIDIA.
  dreaming.hardware.optimus = {
    enable = true;
    nvidiaBusId = "PCI:1:0:0";
    intelBusId = "PCI:0:2:0";
  };

  # Fingerprint for lock/sudo etc.; disabled at boot below (need password for fscrypt).
  services.fprintd.enable = true;
  # Boot/login: password only (no biometrics). Fingerprint is useless/harmful
  # at greeter with fscrypt home
  security.pam.services.login.fprintAuth = false;
  security.pam.services.greetd.fprintAuth = false;
  security.pam.services.dms-greeter.fprintAuth = false;

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "trackpad-i2c-reset" ''
      exec ${rebindTrackpad}
    '')
    setHaptic
  ];

  systemd.services.trackpad-haptic-intensity = {
    description = "Set Synaptics haptic click intensity";
    wantedBy = ["multi-user.target"];
    after = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${setHapticBoot}";
    };
  };
}
