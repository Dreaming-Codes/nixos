{pkgs, ...}: {
  boot = {
    loader.limine.enable = true;
    loader.efi.canTouchEfiVariables = true;
    consoleLogLevel = 0;
    initrd = {
      systemd.enable = true;
      verbose = false;
    };
    tmp.useTmpfs = true;
    kernelParams = ["acpi_call" "quiet"];
  };

  # Console font
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-120n.psf.gz";
    packages = with pkgs; [terminus_font];
  };
}
