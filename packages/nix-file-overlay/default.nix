{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "nix-file-overlay";
  version = "0.1.0";

  src = ./.;

  cargoHash = "sha256-ota0DjsOQrzxVclAS7u0/vo/RbMN3x5d+ucHkLsL79Q=";

  meta = with lib; {
    description = "Temporarily override Nix-managed files with bind mounts";
    license = licenses.mit;
    maintainers = [];
  };
}
