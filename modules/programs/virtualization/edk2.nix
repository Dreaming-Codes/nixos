{pkgs, ...}: let
  edk2-patch_intel = pkgs.fetchpatch {
    url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/EDK2/intel-edk2-stable202505.patch";
    hash = "sha256-4R73SThzykIC4/gYd/Gh+McZ2CUfwrXpKAurKucZLuw=";
    # Convert to DOS line endings
    # https://github.com/Scrut1ny/Hypervisor-Phantom/issues/43#top
    decode = "sed 's/$/\\r/'";
  };

  edk2-spoof-script = ./edk2/edk2-spoof.sh;

  patched-edk2 = pkgs.edk2.overrideAttrs (finalAttrs: previousAttrs: {
    patches = [edk2-patch_intel];
  });
in {
  nixpkgs.overlays = [
    (final: prev: {
      OVMF = prev.OVMF.overrideAttrs (finalAttrs: previousAttrs: {
        patches = (previousAttrs.patches or []) ++ [edk2-patch_intel];

        postPatch =
          (previousAttrs.postPatch or "")
          + ''
            # Run EDK2 spoofing script
            cp ${edk2-spoof-script} ./edk2-spoof.sh
            chmod +x ./edk2-spoof.sh

            # Create log directory
            mkdir -p logs

            # Set environment variables for the script
            export LOG_PATH="$(pwd)/logs"
            export LOG_FILE="$LOG_PATH/$(date +%s).log"

            # Run the spoofing script
            ./edk2-spoof.sh || true
          '';
      });
    })
  ];
}
