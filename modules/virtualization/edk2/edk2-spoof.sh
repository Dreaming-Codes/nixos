#!/usr/bin/env bash

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

function fmtr::format_text() {
  local prefix="$1"
  local text="$2"
  local suffix="$3"
  local codes="${*:4}"
  echo -e "${prefix}${codes// /}${text}${RESET}${suffix}"
}

function fmtr::ask() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[?]" " ${text}" "$TEXT_BLACK" "$BACK_BRIGHT_GREEN")"
  echo "$message" | tee -a "$LOG_FILE"
}

function fmtr::log() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[+]" " ${text}" "$TEXT_BRIGHT_GREEN")"
  echo "$message" | tee -a "$LOG_FILE"
}

function fmtr::info() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[i]" " ${text}" "$TEXT_BRIGHT_CYAN")"
  echo "$message" | tee -a "$LOG_FILE"
}

function fmtr::warn() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[!]" " ${text}" "$TEXT_BRIGHT_YELLOW")"
  echo "$message" | tee -a "$LOG_FILE"
}

function fmtr::error() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[-]" " ${text}" "$TEXT_BRIGHT_RED")"
  echo "$message" >&2
  echo "$message" &>> "$LOG_FILE"
}

function fmtr::fatal() {
  local text="$1"
  local message="$(fmtr::format_text \
    '\n  ' "[X] ${text}" '' "$TEXT_RED" "$BOLD")"
  echo "$message" >&2
  echo "$message" &>> "$LOG_FILE"
}

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

declare -r CPU_VENDOR=$(case "$VENDOR_ID" in
  *AuthenticAMD*) echo "amd" ;;
  *GenuineIntel*) echo "intel" ;;
  *) fmtr::error "Unknown CPU Vendor ID."; exit 1 ;;
esac)

readonly EDK2_VERSION="edk2-stable202505"

patch_ovmf() {
  fmtr::log "Spoofing EDK2/OVMF identifiers..."
  
  # Apply hosts Boot Graphics Resource Table (BGRT) image
  fmtr::info "Applying host's BGRT image to OVMF..."
  
  image_file=$(find /sys/firmware/acpi/bgrt/ -type f -exec file {} \; 2>/dev/null | grep -i 'bitmap' | cut -d: -f1 | head -n1)
  if [ -n "$image_file" ] && [ -f "$image_file" ]; then
    cp -f "$image_file" "MdeModulePkg/Logo/Logo.bmp" 2>/dev/null || true
    fmtr::info "Host BGRT logo image copied successfully."
  else
    fmtr::info "No host BGRT bitmap image found, using default logo."
  fi
}

main() {
  fmtr::log "Starting EDK2/OVMF spoofing process..."
  patch_ovmf
  fmtr::info "EDK2/OVMF spoofing completed."
}

main