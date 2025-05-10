{pkgs, ...}: let
  hypervisor-phantom_intel = {
    main = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/QEMU/intel-qemu-9.2.0.patch";
      hash = "sha256-Rs4piJaLCdUO/iQuzgzOKwp2fOU8QtLQgJx6Y6KazIg=";
    };
    libnfs6 = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/QEMU/qemu-9.2.0-libnfs6.patch";
      hash = "sha256-HjZbgwWf7oOyvhJ4WKFQ996e9+3nVAjTPSzJfyTdF+4=";
    };
    cpu = builtins.readFile ./cpu.patch;
  };
  qemuSpoof = builtins.readFile ./qemu-spoof.sh;
  patched-qemu = pkgs.qemu.overrideAttrs (finalAttrs: previousAttrs: {
    patches = [
      hypervisor-phantom_intel.main
      hypervisor-phantom_intel.libnfs6
    ];
    postPatch = ''
      ${previousAttrs.postPatch}
      CPU_VENDOR=intel
      QEMU_VERSION=9.2.0
      MANUFACTURER="Intel"
      echo "applying dynamic patches"
      ${qemuSpoof}
    '';
  });
in {
  virtualisation.libvirtd = {
    qemu = {
      package = pkgs.qemu;
    };
  };

  environment.etc = {
    spoofedQemu = {
      source = patched-qemu;
    };
  };

  environment.systemPackages = [pkgs.qemu patched-qemu];
}
