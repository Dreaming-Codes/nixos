self: super: let
  # Define local variables to avoid recursion
  hypervisor-phantom_intel = {
    main = super.fetchurl {
      url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/QEMU/intel-qemu-10.0.2.patch";
      sha256 = "sha256-helpedyXwc3SSbJnkI/KQ1BfH84BxSKNMCZGyrGqGy4=";
    };
    libnfs6 = super.fetchurl {
      url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/QEMU/libnfs6-qemu-10.0.2.patch";
      sha256 = "sha256-8DYaDJgNqjExUfEF9NMAv/IpmsJTDeGebQuk3r2F6BQ=";
    };
  };

  qemuSpoofScript = super.writeTextFile {
    name = "qemu-spoof.sh";
    text = builtins.readFile ./qemu-spoof.sh;
    executable = true;
  };

  fakeBatteryFile = ./fake_battery.dsl;
  dmiDataFile = ./dmi_data.txt;

  # Now define patched-qemu using the local variables
  patched-qemu = super.qemu.overrideAttrs (finalAttrs: previousAttrs: {
    patches = [
      hypervisor-phantom_intel.main
      hypervisor-phantom_intel.libnfs6
    ];
    nativeBuildInputs =
      (previousAttrs.nativeBuildInputs or [])
      ++ [
        super.dmidecode
        super.util-linux # provides lscpu
      ];

    # Disable sandbox to allow DMI access for spoofing
    __noChroot = true;
    postPatch = ''
      ${previousAttrs.postPatch or ""}

      # Copy fake battery file to build directory
      cp ${fakeBatteryFile} ./fake_battery.dsl

      # Copy DMI data file to build directory
      cp ${dmiDataFile} ./dmi_data.txt

      # Set up environment and run spoofing script
      export CPU_VENDOR=intel
      export QEMU_VERSION=10.0.2
      export MANUFACTURER="Intel"
      export LOG_PATH="$(pwd)/logs"
      export LOG_FILE="$LOG_PATH/$(date +%s).log"

      mkdir -p logs

      echo "applying dynamic patches"
      ${qemuSpoofScript}  # This will be the store path of the script
    '';
  });
in {
  # Expose the patched-qemu package
  inherit patched-qemu;
}
