{pkgs, ...}: let
  edk2-patch_intel = pkgs.fetchpatch {
    url = "https://raw.githubusercontent.com/Scrut1ny/Hypervisor-Phantom/refs/heads/main/Hypervisor-Phantom/patches/EDK2/intel-edk2-stable202502.patch";
    hash = "sha256-UvgZA3fJCLf7wswaJDVLnc2qNLhabTn1kwdYkobIxk4=";
    # Convert to DOS line endings
    # https://github.com/Scrut1ny/Hypervisor-Phantom/issues/43#top
    decode = "sed 's/$/\\r/'";
  };
  patched-edk2 = pkgs.edk2.overrideAttrs (finalAttrs: previousAttrs: {
    patches = [edk2-patch_intel];
  });
in {
  nixpkgs.overlays = [
    (final: prev: {
      OVMF = prev.OVMF.overrideAttrs (finalAttrs: previousAttrs: {
        patches = (previousAttrs.patches or []) ++ [edk2-patch_intel];
      });
    })
  ];
}
