{
  lib,
  rustPlatform,
  pipewire,
  makeWrapper,
}:
rustPlatform.buildRustPackage {
  pname = "ee-bluez-autoswitch";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [makeWrapper];

  # Wrap the binary so it finds pw-cli and the SPA plugins / pipewire client
  # config that pipewire-native needs to bootstrap.
  postFixup = ''
    wrapProgram "$out/bin/ee-bluez-autoswitch" \
      --prefix PATH : ${lib.makeBinPath [pipewire]} \
      --set-default SPA_PLUGIN_DIR ${pipewire}/lib/spa-0.2 \
      --set-default PIPEWIRE_CONFIG_DIR ${pipewire}/share/pipewire
  '';

  meta = with lib; {
    description = "Force Bluetooth HFP profile when EasyEffects is feeding from a bluez microphone";
    longDescription = ''
      Workaround for https://github.com/wwmm/easyeffects/issues/4878 .
      WirePlumber's autoswitch-bluetooth-profile script only switches a
      bluez card to HFP when an app records directly from the bluez source.
      When EasyEffects sits between apps and the bluez mic via virtual nodes,
      the autoswitch script can't traverse that path and leaves the card on
      A2DP, so the mic stays silent. This watcher attaches to PipeWire and
      forces HFP whenever EasyEffects is wired to a bluez input and an app
      is recording from easyeffects_source.
    '';
    license = licenses.mit;
    mainProgram = "ee-bluez-autoswitch";
    platforms = platforms.linux;
  };
}
