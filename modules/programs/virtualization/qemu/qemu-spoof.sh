if [[ -z "$LOG_PATH" || -z "$LOG_FILE" ]]; then

  readonly LOG_PATH="$(pwd)/logs"
  export LOG_PATH

  readonly LOG_FILE="${LOG_PATH}/$(date +%s).log"
  export LOG_FILE

  # makes sure the log file is created successfully
  if ! ( mkdir -p "$LOG_PATH" && touch "$LOG_FILE" ); then
    exit 1
  fi

fi

# Get CPU vendor ID for later use
readonly VENDOR_ID=$(lscpu | grep 'Vendor ID:' | awk '{print $3}')

function dbg::fail() {
  fmtr::fatal "$1"
  exit 1
}

#
# A library to format text in the terminal.
# The ANSI text color and style codes are all provided as environment variables
# and can be easily used in the standardized function "format_text".
# For messages to the user use the
# ask, log, info, warn, error and fatal wrapper functions.
# And for important information and titles, you may use box_text
#

# exports ANSI codes as read-only variables
declare -xr RESET="\033[0m"
# text styles
declare -xr BOLD="\033[1m"
declare -xr DIM="\033[2m"
declare -xr ITALIC="\033[3m"
declare -xr UNDER="\033[4m"
declare -xr BLINK="\033[5m"
declare -xr REVERSE="\033[7m"
declare -xr HIDDEN="\033[8m"
declare -xr STRIKE="\033[9m"
# text colors
declare -xr TEXT_BLACK="\033[30m"; declare -xr TEXT_GRAY="\033[90m"
declare -xr TEXT_RED="\033[31m"; declare -xr TEXT_BRIGHT_RED="\033[91m"
declare -xr TEXT_GREEN="\033[32m"; declare -xr TEXT_BRIGHT_GREEN="\033[92m"
declare -xr TEXT_YELLOW="\033[33m"; declare -xr TEXT_BRIGHT_YELLOW="\033[93m"
declare -xr TEXT_BLUE="\033[34m"; declare -xr TEXT_BRIGHT_BLUE="\033[94m"
declare -xr TEXT_MAGENTA="\033[35m"; declare -xr TEXT_BRIGHT_MAGENTA="\033[95m"
declare -xr TEXT_CYAN="\033[36m"; declare -xr TEXT_BRIGHT_CYAN="\033[96m"
declare -xr TEXT_WHITE="\033[37m"; declare -xr TEXT_BRIGHT_WHITE="\033[97m"
# background colors
declare -xr BACK_BLACK="\033[40m"; declare -xr BACK_GRAY="\033[100m"
declare -xr BACK_RED="\033[41m"; declare -xr BACK_BRIGHT_RED="\033[101m"
declare -xr BACK_GREEN="\033[42m"; declare -xr BACK_BRIGHT_GREEN="\033[102m"
declare -xr BACK_YELLOW="\033[43m"; declare -xr BACK_BRIGHT_YELLOW="\033[103m"
declare -xr BACK_BLUE="\033[44m"; declare -xr BACK_BRIGHT_BLUE="\033[104m"
declare -xr BACK_MAGENTA="\033[45m"; declare -xr BACK_BRIGHT_MAGENTA="\033[105m"
declare -xr BACK_CYAN="\033[46m"; declare -xr BACK_BRIGHT_CYAN="\033[106m"
declare -xr BACK_WHITE="\033[47m"; declare -xr BACK_BRIGHT_WHITE="\033[107m"

###############################################################
# Formats a part of the provided string using ANSI escape codes
# Globals:
#   RESET: The escape code that resets formatting
# Arguments:
#   $1: Unformatted text before $2
#   $2: The text to be formatted
#   $3: Unformatted text after $2
#   ${*:4}: ANSI codes to set on $2
# Outputs:
#   Writes complete string with ANSI codes to STDOUT
###############################################################
function fmtr::format_text() {
  local prefix="$1"
  local text="$2"
  local suffix="$3"
  local codes="${*:4}"
  echo -e "${prefix}${codes// /}${text}${RESET}${suffix}"
}

#######################################################
# Provides stylized decorations for prompts to the user
# Globals:
#   TEXT_BLACK
#   BACK_BRIGHT_GREEN
# Arguments:
#   Question to ask to the user
# Outputs:
#   Formatted question for the user to STDOUT
#######################################################
function fmtr::ask() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[?]" " ${text}" "$TEXT_BLACK" "$BACK_BRIGHT_GREEN")"
  echo "$message" | tee -a "$LOG_FILE"
}

################################################
# Provides stylized decorations for log messages
# Globals:
#   TEXT_BRIGHT_GREEN
# Arguments:
#   Message to log
# Outputs:
#   Formatted log message to STDOUT
################################################
function fmtr::log() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[+]" " ${text}" "$TEXT_BRIGHT_GREEN")"
  echo "$message" | tee -a "$LOG_FILE"
}

########################################################
# Provides stylized decorations for messages to the user
# Globals:
#   TEXT_BRIGHT_CYAN
# Arguments:
#   The message to the user
# Outputs:
#   Formatted info message
########################################################
function fmtr::info() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[i]" " ${text}" "$TEXT_BRIGHT_CYAN")"
  echo "$message" | tee -a "$LOG_FILE"
}

########################################################
# Provides stylized decorations for warnings to the user
# Globals:
#   TEXT_BRIGHT_YELLOW
# Arguments:
#   The important message to the user
# Outputs:
#   Formatted warning
########################################################
function fmtr::warn() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[!]" " ${text}" "$TEXT_BRIGHT_YELLOW")"
  echo "$message" | tee -a "$LOG_FILE"
}

##############################################################
# Provides stylized decorations for recoverable error messages
# Globals:
#   TEXT_BRIGHT_RED
# Arguments:
#   The error to print
# Outputs:
#   Formatted error message
########################################################
function fmtr::error() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[-]" " ${text}" "$TEXT_BRIGHT_RED")"
  echo "$message" >&2
  echo "$message" &>> "$LOG_FILE"
}

##############################################################
# Provides stylized decorations for fatal/unrecoverable errors
# Globals:
#   TEXT_BRIGHT_CYAN
#   BOLD
# Arguments:
#   The fatal error message
# Outputs:
#   Formatted error message
##############################################################
function fmtr::fatal() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[X] ${text}" '' "$TEXT_RED" "$BOLD")"
  echo "$message" >&2
  echo "$message" &>> "$LOG_FILE"
}

#################################################
# Draws a beautiful box around a provided string
# Arguments:
#   String to format
# Outputs:
#   Writes text box to STDOUT in multiple strings
#################################################
function fmtr::box_text() {
  local text="$1"
  local width=$((${#text} + 2))

  # top decoration
  printf "\n  ╔"
  printf "═%.0s" $(seq 1 $width)
  printf "╗\n"

  # pastes text into middle
  printf "  ║ %s ║\n" "$text"

  # bottom decoration
  printf "  ╚"
  printf "═%.0s" $(seq 1 $width)
  printf "╝\n"
}

spoof_serial_numbers() {
  local patterns=(STRING_SERIALNUMBER STR_SERIALNUMBER STR_SERIAL_MOUSE \
                  STR_SERIAL_TABLET STR_SERIAL_KEYBOARD STR_SERIAL_COMPAT)
  for file in ./hw/usb/*.c; do
    for pat in "${patterns[@]}"; do
      grep -n "\[\s*${pat}\s*\]\s*=\s*\"[^\"]*\"" "$file" | cut -d: -f1 | while read -r lineno; do
        serial=$(tr -dc 'A-Z0-9' </dev/urandom | head -c10)
        sed -r -i "${lineno}s/(\[\s*${pat}\s*\]\s*=\s*\")[^\"]*(\")/\1${serial}\2/" "$file"
      done
    done
  done
}

spoof_drive_serial_number() {
  local core_file="hw/ide/core.c"

  local ide_cd_models=(
    "HL-DT-ST BD-RE WH16NS60" "HL-DT-ST DVDRAM GH24NSC0"
    "HL-DT-ST BD-RE BH16NS40" "HL-DT-ST DVD+-RW GT80N"
    "HL-DT-ST DVD-RAM GH22NS30" "HL-DT-ST DVD+RW GCA-4040N"
    "Pioneer BDR-XD07B" "Pioneer DVR-221LBK" "Pioneer BDR-209DBK"
    "Pioneer DVR-S21WBK" "Pioneer BDR-XD05B" "ASUS BW-16D1HT"
    "ASUS DRW-24B1ST" "ASUS SDRW-08D2S-U" "ASUS BC-12D2HT"
    "ASUS SBW-06D2X-U" "Samsung SH-224FB" "Samsung SE-506BB"
    "Samsung SH-B123L" "Samsung SE-208GB" "Samsung SN-208DB"
    "Sony NEC Optiarc AD-5280S" "Sony DRU-870S" "Sony BWU-500S"
    "Sony NEC Optiarc AD-7261S" "Sony AD-7200S" "Lite-On iHAS124-14"
    "Lite-On iHBS112-04" "Lite-On eTAU108" "Lite-On iHAS324-17"
    "Lite-On eBAU108" "HP DVD1260i" "HP DVD640"
    "HP BD-RE BH30L" "HP DVD Writer 300n" "HP DVD Writer 1265i"
  )

  local ide_cfata_models=(
    "SanDisk Ultra microSDXC UHS-I" "SanDisk Extreme microSDXC UHS-I"
    "SanDisk High Endurance microSDXC" "SanDisk Industrial microSD"
    "SanDisk Mobile Ultra microSDHC" "Samsung EVO Select microSDXC"
    "Samsung PRO Endurance microSDHC" "Samsung PRO Plus microSDXC"
    "Samsung EVO Plus microSDXC" "Samsung PRO Ultimate microSDHC"
    "Kingston Canvas React Plus microSD" "Kingston Canvas Go! Plus microSD"
    "Kingston Canvas Select Plus microSD" "Kingston Industrial microSD"
    "Kingston Endurance microSD" "Lexar Professional 1066x microSDXC"
    "Lexar High-Performance 633x microSDHC" "Lexar PLAY microSDXC"
    "Lexar Endurance microSD" "Lexar Professional 1000x microSDHC"
    "PNY Elite-X microSD" "PNY PRO Elite microSD"
    "PNY High Performance microSD" "PNY Turbo Performance microSD"
    "PNY Premier-X microSD" "Transcend High Endurance microSDXC"
    "Transcend Ultimate microSDXC" "Transcend Industrial Temp microSD"
    "Transcend Premium microSDHC" "Transcend Superior microSD"
    "ADATA Premier Pro microSDXC" "ADATA XPG microSDXC"
    "ADATA High Endurance microSDXC" "ADATA Premier microSDHC"
    "ADATA Industrial microSD" "Toshiba Exceria Pro microSDXC"
    "Toshiba Exceria microSDHC" "Toshiba M203 microSD"
    "Toshiba N203 microSD" "Toshiba High Endurance microSD"
  )

  local default_models=(
    "Samsung SSD 970 EVO 1TB" "Samsung SSD 860 QVO 1TB"
    "Samsung SSD 850 PRO 1TB" "Samsung SSD T7 Touch 1TB"
    "Samsung SSD 840 EVO 1TB" "WD Blue SN570 NVMe SSD 1TB"
    "WD Black SN850 NVMe SSD 1TB" "WD Green 1TB SSD"
    "WD Blue 3D NAND 1TB SSD" "Crucial P3 1TB PCIe 3.0 3D NAND NVMe SSD"
    "Seagate BarraCuda SSD 1TB" "Seagate FireCuda 520 SSD 1TB"
    "Seagate IronWolf 110 SSD 1TB" "SanDisk Ultra 3D NAND SSD 1TB"
    "Seagate Fast SSD 1TB" "Crucial MX500 1TB 3D NAND SSD"
    "Crucial P5 Plus NVMe SSD 1TB" "Crucial BX500 1TB 3D NAND SSD"
    "Crucial P3 1TB PCIe 3.0 3D NAND NVMe SSD"
    "Kingston A2000 NVMe SSD 1TB" "Kingston KC2500 NVMe SSD 1TB"
    "Kingston A400 SSD 1TB" "Kingston HyperX Savage SSD 1TB"
    "SanDisk SSD PLUS 1TB" "SanDisk Ultra 3D 1TB NAND SSD"
  )

  get_random_element() {
    local array=("$@")
    echo "${array[RANDOM % ${#array[@]}]}"
  }

  local new_ide_cd_model=$(get_random_element "${ide_cd_models[@]}")
  local new_ide_cfata_model=$(get_random_element "${ide_cfata_models[@]}")
  local new_default_model=$(get_random_element "${default_models[@]}")

  sed -i "$core_file" -Ee "s/\"HL-DT-ST BD-RE WH16NS60\"/\"${new_ide_cd_model}\"/"
  sed -i "$core_file" -Ee "s/\"Hitachi HMS360404D5CF00\"/\"${new_ide_cfata_model}\"/"
  sed -i "$core_file" -Ee "s/\"Samsung SSD 980 500GB\"/\"${new_default_model}\"/"

}

spoof_acpi_table_data() {
  local oem_pairs=(
    'DELL  ' 'Dell Inc' ' ASUS ' 'Notebook'
    'MSI NB' 'MEGABOOK' 'LENOVO' 'TC-O5Z  '
    'LENOVO' 'CB-01   ' 'SECCSD' 'LH43STAR'
    'LGE   ' 'ICL     '
  )

  if [[ "$CPU_VENDOR" == "amd" ]]; then
    oem_pairs+=('ALASKA' 'A M I ')
  elif [[ "$CPU_VENDOR" == "intel" ]]; then
    oem_pairs+=('INTEL ' 'U Rvp   ')
  fi

  local total_pairs=$(( ${#oem_pairs[@]} / 2 ))
  local random_index=$(( RANDOM % total_pairs * 2 ))
  local appname6=${oem_pairs[$random_index]}
  local appname8=${oem_pairs[$random_index + 1]}
  local h_file="include/hw/acpi/aml-build.h"

  sed -i "$h_file" -e "s/^#define ACPI_BUILD_APPNAME6 \".*\"/#define ACPI_BUILD_APPNAME6 \"${appname6}\"/"
  sed -i "$h_file" -e "s/^#define ACPI_BUILD_APPNAME8 \".*\"/#define ACPI_BUILD_APPNAME8 \"${appname8}\"/"

  fmtr::info "Obtaining machine's chassis-type..."

  local c_file="hw/acpi/aml-build.c"
  local pm_type="1" # Desktop
  local chassis_type=$(sudo dmidecode --string chassis-type)

  if [[ "$chassis_type" = "Notebook" ]]; then
    pm_type="2" # Notebook/Laptop/Mobile
  fi

  sed -i 's/build_append_int_noprefix(tbl, 0 \/\* Unspecified \*\//build_append_int_noprefix(tbl, '"$pm_type"' \/\* '"$chassis_type"' \*\//g' "$c_file"

  if [[ "$chassis_type" = "Notebook" ]]; then    
    fmtr::warn "Host PM type equals '$pm_type' ($chassis_type)"
    fmtr::info "Generating fake battery SSDT ACPI table..."

    cat "${FAKE_BATTERY_ACPITABLE}" \
      | sed "s/BOCHS/$appname6/" \
      | sed "s/BXPCSSDT/$appname8/" > "$HOME/fake_battery.dsl"
    iasl -tc "$HOME/fake_battery.dsl" &>> "$LOG_FILE"

    fmtr::info "ACPI table saved to '$HOME/fake_battery.aml'"
    fmtr::info "It's highly recommended to passthrough the ACPI Table via QEMU's args/xml:
      qemu-system-x86_64 -acpitable '$HOME/fake_battery.aml'"
  fi

}

spoof_smbios_processor_data() {
  local chipset_file
  case "$QEMU_VERSION" in
    "8.2.6") chipset_file="hw/i386/pc_q35.c" ;;
    "9.2.4"|"10.0.2") chipset_file="hw/i386/fw_cfg.c" ;;
    *) fmtr::warn "Unsupported QEMU version: $QEMU_VERSION" ;;
  esac

  local manufacturer=$(sudo dmidecode --string processor-manufacturer)
  sed -i "$chipset_file" -e "s/smbios_set_defaults(\"[^\"]*\",/smbios_set_defaults(\"${manufacturer}\",/"

  local smbios_file="hw/smbios/smbios.c"
  local t0_raw="/sys/firmware/dmi/entries/0-0/raw"

  [[ -e $t0_raw ]] || sudo modprobe dmi_sysfs >>"$LOG_FILE"

  local data=$(sudo hexdump -v -e '/1 "%02X"' "$t0_raw")

  local rom_size="${data:18:2}"
  local bios_characteristics="$(echo "${data:20:16}" | fold -w2 | tac | tr -d '\n')"
  local characteristics_ext1="${data:36:2}"
  local characteristics_ext2="${data:38:2}"

  local t4_raw="/sys/firmware/dmi/entries/4-0/raw"

  [[ -e $t4_raw ]] || sudo modprobe dmi_sysfs >>"$LOG_FILE"

  # Try to read from pre-extracted DMI data file first, fallback to system DMI
  if [[ -f "./dmi_data.txt" ]]; then
    local data=$(cat ./dmi_data.txt)
    fmtr::info "Using pre-extracted DMI data"
  else
    local data=$(sudo hexdump -v -e '/1 "%02X"' "$t4_raw" 2>/dev/null || echo "")
  fi

  # Check if DMI data is valid, use fallbacks if not
  if [[ -z "$data" || ${#data} -lt 84 ]]; then
    # Fallback values for Intel Core i7
    local processor_family="CD"
    local voltage="89" 
    local external_clock="6400"
    local processor_upgrade="01"
    local l1_cache_handle="FFFF"
    local l2_cache_handle="FFFF" 
    local l3_cache_handle="FFFF"
    local processor_characteristics="0004"
    local processor_family2="CD00"
  else
    local processor_type="${data:10:2}"
    local processor_family="${data:12:2}"
    local voltage="${data:34:2}"
    local external_clock="${data:38:2}${data:36:2}"
    local max_speed="${data:42:2}${data:40:2}"
    local current_speed="${data:46:2}${data:44:2}"
    local status="${data:48:2}"
    local processor_upgrade="${data:50:2}"
    local l1_cache_handle="${data:54:2}${data:52:2}"
    local l2_cache_handle="${data:58:2}${data:56:2}"
    local l3_cache_handle="${data:62:2}${data:60:2}"
    local processor_characteristics="${data:78:2}${data:76:2}"
    local processor_family2="${data:82:2}${data:80:2}"
  fi

  sed -i -E "s/(t->processor_family[[:space:]]*=[[:space:]]*)0x[0-9A-Fa-f]+;/\10x${processor_family};/" "$smbios_file"
  sed -i -E "s/(t->voltage[[:space:]]*=[[:space:]]*)0;/\10x${voltage};/" "$smbios_file"
  sed -i -E "s/(t->external_clock[[:space:]]*=[[:space:]]*cpu_to_le16\()0x[0-9A-Fa-f]+(\);)/\10x${external_clock}\2/" "$smbios_file"
  sed -i -E "s/(t->l1_cache_handle[[:space:]]*=[[:space:]]*cpu_to_le16\()0x[0-9A-Fa-f]+(\);)/\10x${l1_cache_handle}\2/" "$smbios_file"
  sed -i -E "s/(t->l2_cache_handle[[:space:]]*=[[:space:]]*cpu_to_le16\()0x[0-9A-Fa-f]+(\);)/\10x${l2_cache_handle}\2/" "$smbios_file"
  sed -i -E "s/(t->l3_cache_handle[[:space:]]*=[[:space:]]*cpu_to_le16\()0x[0-9A-Fa-f]+(\);)/\10x${l3_cache_handle}\2/" "$smbios_file"
  sed -i -E "s/(t->processor_upgrade[[:space:]]*=[[:space:]]*)0x[0-9A-Fa-f]+;/\10x${processor_upgrade};/" "$smbios_file"
  sed -i -E "s/(t->processor_characteristics[[:space:]]*=[[:space:]]*cpu_to_le16\()0x[0-9A-Fa-f]+(\);)/\10x${processor_characteristics}\2/" "$smbios_file"
  sed -i -E "s/(t->processor_family2[[:space:]]*=[[:space:]]*cpu_to_le16\()0x[0-9A-Fa-f]+(\);)/\10x${processor_family2}\2/" "$smbios_file"

}

declare -r CPU_VENDOR=$(case "$VENDOR_ID" in
  *AuthenticAMD*) echo "amd" ;;
  *GenuineIntel*) echo "intel" ;;
  *) fmtr::error "Unknown CPU Vendor ID."; exit 1 ;;
esac)

readonly QEMU_VERSION="10.0.2"
readonly FAKE_BATTERY_ACPITABLE="fake_battery.dsl"

main() {
  fmtr::log "Spoofing all unique hardcoded QEMU identifiers..."
  
  spoof_serial_numbers
  spoof_drive_serial_number
  spoof_smbios_processor_data
  spoof_acpi_table_data
}

main
