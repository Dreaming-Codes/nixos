{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.cachykernel;

  # CPU info from nixos-facter report (safely handles missing facter module)
  hasFacter = config ? facter && config.facter ? report && config.facter.report ? hardware;
  cpus =
    if hasFacter
    then config.facter.report.hardware.cpu or []
    else [];
  firstCpu =
    if cpus != []
    then builtins.head cpus
    else {};
  cpuFeatures = firstCpu.features or [];

  hasCpuFeature = feature: builtins.elem feature cpuFeatures;

  # Detect AMD Zen 4+ (family 25 model >= 96 = Zen 4 Phoenix/Dragon Range,
  # or family >= 26 = Zen 5+)
  cpuFamily = firstCpu.family or 0;
  cpuModel = firstCpu.model or 0;
  isZen4Plus =
    (firstCpu.vendor_name or "")
    == "AuthenticAMD"
    && ((cpuFamily == 25 && cpuModel >= 96) || cpuFamily >= 26);

  # x86_64 feature level detection
  # v4 requires AVX-512 foundation
  hasV4 = hasCpuFeature "avx512f" && hasCpuFeature "avx512bw" && hasCpuFeature "avx512vl";
  # v3 requires AVX2, FMA, BMI1/2, MOVBE, F16C
  hasV3 = hasCpuFeature "avx2" && hasCpuFeature "fma" && hasCpuFeature "bmi1" && hasCpuFeature "bmi2";
  # v2 requires SSE4.2, POPCNT, SSSE3, CX16
  hasV2 = hasCpuFeature "sse4_2" && hasCpuFeature "popcnt" && hasCpuFeature "ssse3";

  # Pick the best architecture variant
  # zen4 > v4 > v3 > v2 > generic
  detectedArch =
    if isZen4Plus
    then "zen4"
    else if hasV4
    then "x86_64-v4"
    else if hasV3
    then "x86_64-v3"
    else if hasV2
    then "x86_64-v2"
    else null;

  # Build the kernel package attribute name
  # Format: linuxPackages-cachyos-latest{-lto}{-arch}
  # Note: only the "latest" variant has arch-specific builds
  ltoSuffix = lib.optionalString cfg.lto "-lto";
  archSuffix = lib.optionalString (cfg.cpuArch != null) "-${cfg.cpuArch}";
  kernelAttr = "linuxPackages-cachyos-latest${ltoSuffix}${archSuffix}";
in {
  options.dreamingoptimal.optimization.cachykernel = {
    lto = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable LTO (Link-Time Optimization) variant of the CachyOS kernel.
        Uses Clang ThinLTO for ~2-5% performance improvement and smaller binary size.
      '';
    };

    cpuArch = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "x86_64-v2"
          "x86_64-v3"
          "x86_64-v4"
          "zen4"
        ]
      );
      default = detectedArch;
      defaultText = lib.literalExpression "auto-detected from nixos-facter CPU features";
      description = ''
        CPU architecture variant for the CachyOS kernel.
        Auto-detected from nixos-facter report when available:
        - zen4: AMD Zen 4+ processors
        - x86_64-v4: CPUs with AVX-512 support
        - x86_64-v3: CPUs with AVX2/FMA support (most modern CPUs)
        - x86_64-v2: CPUs with SSE4.2/POPCNT support
        - null: Generic x86_64 build (fallback)
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [inputs.nix-cachyos-kernel.overlays.pinned];
    boot.kernelPackages = pkgs.cachyosKernels.${kernelAttr};

    warnings = lib.optional (!hasFacter) ''
      dreamingoptimal.optimization.cachykernel: nixos-facter report not available.
      CPU architecture could not be auto-detected; falling back to generic kernel (${kernelAttr}).
      For optimal performance, either configure nixos-facter or set
      dreamingoptimal.optimization.cachykernel.cpuArch manually.
    '';
  };
}
