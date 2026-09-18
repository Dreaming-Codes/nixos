{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.dreaming.core.cryptroot-fido-or-pass;
  unlock = pkgs.callPackage (self + "/packages/cryptroot-fido-or-pass") {};
  cryptsetupUnit = "systemd-cryptsetup@${cfg.device}.service";
in {
  options.dreaming.core.cryptroot-fido-or-pass = {
    enable = lib.mkEnableOption ''
      Initrd FIDO2 unlock before passphrase cryptsetup: wait for a YubiKey
      (udev) or Enter for LUKS passphrase, then PIN (empty Enter defers).
      Requires boot.initrd.systemd and a LUKS device named like cfg.device
      with a FIDO2 token enrolled and a passphrase slot. The helper binary
      currently targets mapper name "cryptroot" and
      /dev/disk/by-partlabel/disk-main-root.
    '';

    device = lib.mkOption {
      type = lib.types.str;
      default = "cryptroot";
      description = "dm-crypt / crypttab name (systemd-cryptsetup@<name>).";
    };

    numlock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NumLock in initrd before the unlock prompts.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "dreaming.core.cryptroot-fido-or-pass requires boot.initrd.systemd.enable.";
      }
    ];

    boot.initrd.systemd = {
      fido2.enable = true;
      extraBin = {
        systemd-ask-password = "${pkgs.systemd}/bin/systemd-ask-password";
        # Wait UI uses display-message / hide-message / watch-keystroke.
        plymouth = "${pkgs.plymouth}/bin/plymouth";
      }
      // lib.optionalAttrs cfg.numlock {
        setleds = "${pkgs.kbd}/bin/setleds";
      };
      storePaths = [
        unlock
        pkgs.libfido2
        pkgs.systemd
        "${pkgs.systemd}/lib/cryptsetup"
      ];
      services = lib.mkMerge [
        (lib.mkIf cfg.numlock {
          numlock = {
            description = "Enable NumLock";
            wantedBy = ["initrd.target"];
            before = ["cryptsetup-pre.target" "cryptroot-fido-or-pass.service"];
            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "/bin/sh -c 'for t in /dev/tty[1-8]; do [ -c \"$t\" ] && /bin/setleds -D +num < \"$t\" || true; done'";
            };
          };
        })
        {
          cryptroot-fido-or-pass = {
            description = "Unlock ${cfg.device} via FIDO2 (empty PIN defers to passphrase)";
            wantedBy = ["cryptsetup.target"];
            before = [cryptsetupUnit];
            after =
              [
                "systemd-udevd.service"
                "cryptsetup-pre.target"
                "plymouth-start.service"
                "systemd-ask-password-plymouth.service"
              ]
              ++ lib.optionals cfg.numlock ["numlock.service"];
            wants = ["systemd-udevd.service"];
            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = "infinity";
              SuccessExitStatus = "0 1";
              ExecStart = "${unlock}/bin/cryptroot-fido-or-pass";
            };
          };
        }
      ];
    };
  };
}
