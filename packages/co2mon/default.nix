{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  udev,
}:
# Upstream ships no CLI or Cargo.lock; the `watch` example is installed as `co2mon`.
rustPlatform.buildRustPackage {
  pname = "co2mon";
  version = "2.1.1-unstable-2023-03-21";

  src = fetchFromGitHub {
    owner = "lnicola";
    repo = "co2mon";
    rev = "a1c25504b58bc1926cb4aeb0c05cd92c86ba1578";
    hash = "sha256-1ZCIevJzIfp0/bdjFRU0JzAoesy0FgBIMi4cG7S7FP0=";
  };

  cargoLock.lockFile = ./Cargo.lock;
  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [pkg-config];
  buildInputs = [udev];

  buildNoDefaultFeatures = true;
  buildFeatures = ["linux-static-hidraw"];
  cargoBuildFlags = ["-p" "co2mon" "--example" "watch"];
  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm755 target/*/release/examples/watch $out/bin/co2mon
    runHook postInstall
  '';

  meta = {
    description = "Read CO2/temperature from Holtek ZyTemp USB sensors (TFA AirCO2ntrol Mini)";
    homepage = "https://github.com/lnicola/co2mon";
    license = with lib.licenses; [mit asl20];
    mainProgram = "co2mon";
    platforms = lib.platforms.linux;
  };
}
