{
  lib,
  stdenvNoCC,
  python3,
  librsvg,
}:
stdenvNoCC.mkDerivation {
  pname = "plymouth-neuralink";
  version = "0.1.0";
  outputs = ["out" "limine"];

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./generate.py ./neuralink.script ./neuralink-logo.svg];
  };

  nativeBuildInputs = [librsvg (python3.withPackages (ps: [ps.pillow ps.numpy]))];

  buildPhase = ''
    runHook preBuild
    python3 generate.py theme neuralink.script neuralink-logo.svg limine
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    dir=$out/share/plymouth/themes/neuralink
    mkdir -p $dir
    cp theme/* $dir/
    cat > $dir/neuralink.plymouth <<EOF
    [Plymouth Theme]
    Name=Neuralink
    Description=Animated neural link implant
    ModuleName=script

    [script]
    ImageDir=$dir
    ScriptFile=$dir/neuralink.script
    EOF
    mkdir -p $limine
    cp limine/* $limine/
    runHook postInstall
  '';

  meta = {
    description = "Animated Neuralink-inspired Plymouth theme";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
