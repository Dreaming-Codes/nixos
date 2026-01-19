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
  version = "0.1.0";

  src = ./.;

  cargoHash = "sha256-cvhoq7isdzwtSzhi00vPshYAIWR/q+uSO7M/I79YNu0=";

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
