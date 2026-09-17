{
  lib,
  pkgs,
  ...
}: let
  # The sensor hub rejects Intel's generic ish_ptl.bin ("ISH loader: cmd 2
  # failed 10"), so no ambient light sensor. The kernel first requests
  # intel/ish/ish_ptl_<crc32 vendor>_<crc32 product>_<crc32 sku>.bin, which
  # this derivation provides from Samsung's "Intel Sensor Hub" Windows driver.
  # Source: Galaxy Books Download Center, model NP960UJG, Sensor -> Intel Sensor Hub.
  driverZip = pkgs.fetchurl {
    name = "BASW-A3934A1A_1063.zip";
    url = "https://org.downloadcenter.samsung.com/downloadfile/ContentsFile.aspx?CttFileID=11724010&CDCttType=DR&ModelType=C&ModelName=&VPath=DR/202609/20260909080633603/BASW-A3934A1A_1063.ZIP";
    hash = "sha256-aHB28cf2kW+uP6C0ws6KYXShMUbfQ/9Yxw4n+MYdeDg=";
  };

  # /sys/class/dmi/id/{sys_vendor,product_name,product_sku}
  dmi = [
    "Samsung"
    "Galaxy Book6 Ultra - PVAL"
    "PVAL-960UJG-PTLH-0"
  ];

  ishFirmware =
    pkgs.runCommand "samsung-galaxybook6-ultra-ish-firmware" {
      nativeBuildInputs = [pkgs.unzip pkgs.python3];
      meta.license = lib.licenses.unfree;
    } ''
      unzip -q ${driverZip} 'IshHeciExtensionTemplate/x64/FwImage/0004/PTL_*.bin'
      fw=$(echo IshHeciExtensionTemplate/x64/FwImage/0004/PTL_*.bin)
      name=$(python3 -c 'import sys, zlib; print("ish_ptl_" + "_".join(f"{zlib.crc32(s.encode()):08x}" for s in sys.argv[1:]) + ".bin")' ${lib.escapeShellArgs dmi})
      install -Dm644 "$fw" "$out/lib/firmware/intel/ish/$name"
    '';
in {
  hardware.firmware = [ishFirmware];
}
