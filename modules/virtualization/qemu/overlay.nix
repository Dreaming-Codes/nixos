self: super: let
  # Define local variables to avoid recursion
  hypervisor-phantom_intel = {
    main = super.fetchurl {
      url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/QEMU/intel-qemu-9.2.3.patch";
      sha256 = "sha256-ONxMuNicvwB0lE8uL3o8PIbONhRMbUZVkd7W2cE0pj4=";
    };
    libnfs6 = super.fetchurl {
      url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/QEMU/qemu-9.2.3-libnfs6.patch";
      sha256 = "sha256-HjZbgwWf7oOyvhJ4WKFQ996e9+3nVAjTPSzJfyTdF+4=";
    };
  };

  qemuSpoofScript = super.writeTextFile {
    name = "qemu-spoof.sh";
    text = builtins.readFile ./qemu-spoof.sh;
    executable = true;
  };

  # Now define patched-qemu using the local variables
  patched-qemu = super.qemu.overrideAttrs (finalAttrs: previousAttrs: {
    patches = [
      hypervisor-phantom_intel.main
      hypervisor-phantom_intel.libnfs6
    ];
    postPatch = ''
      ${previousAttrs.postPatch or ""}
      CPU_VENDOR=intel
      QEMU_VERSION=9.2.0
      MANUFACTURER="Intel"
      echo "applying dynamic patches"
      ${qemuSpoofScript}  # This will be the store path of the script
    '';
  });
in {
  # Expose the patched-qemu package
  inherit patched-qemu;
}
