{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
  # hidapi,  # TODO: Re-enable when Keychron custom firmware is ready
  systemd,
}:
rustPlatform.buildRustPackage {
  pname = "ci-keyboard-leds";
  version = "0.2.0";

  src = ./.;

  cargoHash = "sha256-LMjpQLvkU7MRjZKSTHXuKMRhhOQRgn5YikuKgI4YTsA=";

  nativeBuildInputs = [pkg-config];

  buildInputs = [
    openssl
    # hidapi  # TODO: Re-enable when Keychron custom firmware is ready
    systemd
  ];

  meta = with lib; {
    description = "Monitor CI status and display on keyboard numpad LEDs";
    license = licenses.mit;
    maintainers = [];
  };
}
