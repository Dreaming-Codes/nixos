{
  lib,
  rustPlatform,
  fetchFromGitea,
  pkg-config,
  libGL,
  libxkbcommon,
  wayland,
  wayland-protocols,
  wayland-scanner,
  lz4,
}:
rustPlatform.buildRustPackage rec {
  pname = "awww";
  version = "0.11.2";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "LGFae";
    repo = "awww";
    rev = "v${version}";
    hash = "sha256-X2ptpXRo6ps5RxDe5RS7qfTaHWqBbBNw/aSdC2tzUG8=";
  };

  cargoHash = "sha256-5KZWsdo37NbFFkK8XFc0XI9iwBkpV8KsOaOc0y287Io=";

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    wayland
    wayland-protocols
  ];

  buildInputs = [
    libGL
    libxkbcommon
    wayland
    wayland-protocols
    lz4
  ];

  meta = with lib; {
    description = "A simple wallpaper daemon for Wayland";
    homepage = "https://codeberg.org/LGFae/awww";
    license = licenses.mit;
    maintainers = with maintainers; [];
    platforms = platforms.linux;
  };
}
