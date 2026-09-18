{
  lib,
  rustPlatform,
  pkg-config,
  systemd,
}:
rustPlatform.buildRustPackage {
  pname = "cryptroot-fido-or-pass";
  version = "0.1.0";

  src = ./.;

  cargoHash = "sha256-Qg6sWjB57jifJLiYR1BlH7rmbnipDc8YDxEyg1qFJCk=";

  nativeBuildInputs = [pkg-config];
  buildInputs = [systemd];

  meta = with lib; {
    description = "Initrd FIDO2 unlock for cryptroot with passphrase defer";
    license = licenses.mit;
    mainProgram = "cryptroot-fido-or-pass";
  };
}
