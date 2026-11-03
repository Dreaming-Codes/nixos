{
  lib,
  kernel,
  ipu7-drivers,
}:
# From 6.17 the upstream Makefile builds only intel-ipu7-psys, against the
# in-tree intel_ipu7 core and ISYS.
ipu7-drivers.overrideAttrs (old: {
  pname = "ipu7-psys";

  patches = (old.patches or []) ++ [./psys-in-tree-abi.patch];

  meta =
    old.meta
    // {
      description = "Intel IPU7 PSYS module built against the in-tree intel_ipu7 core";
      broken = kernel.kernelOlder "6.17";
    };
})
