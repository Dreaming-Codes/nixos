{...}: {
  config.boot = {
    consoleLogLevel = 0;
    initrd = {
      systemd.enable = true;
      verbose = false;
    };
    tmp.useTmpfs = true;
    kernelParams = ["acpi_call" "quiet"];
  };
}
