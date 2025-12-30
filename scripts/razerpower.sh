#!/bin/bash

# Razer power mode control script for ashell custom module
# Power modes: 0=Balanced, 1=Gaming, 2=Creator, 3=Silent, 4=Custom

get_power_mode() {
    local ac_state="$1"
    local output
    output=$(razer-cli read power "$ac_state" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "error"
        return 1
    fi
    # Extract power level from output like "RES: GetPwrLevel { pwr: 1 }"
    echo "$output" | grep -oP 'pwr: \K[0-9]+'
}

mode_to_name() {
    case "$1" in
        0) echo "balanced" ;;
        1) echo "gaming" ;;
        2) echo "creator" ;;
        3) echo "silent" ;;
        4) echo "custom" ;;
        *) echo "unknown" ;;
    esac
}

mode_to_display() {
    case "$1" in
        0) echo "Balanced" ;;
        1) echo "Gaming" ;;
        2) echo "Creator" ;;
        3) echo "Silent" ;;
        4) echo "Custom" ;;
        *) echo "Unknown" ;;
    esac
}

output_json() {
    local ac_mode bat_mode ac_name bat_name
    ac_mode=$(get_power_mode "ac")
    bat_mode=$(get_power_mode "bat")
    
    if [[ "$ac_mode" == "error" ]] || [[ "$bat_mode" == "error" ]]; then
        echo '{"text": "!", "alt": "error"}'
        return
    fi
    
    ac_name=$(mode_to_name "$ac_mode")
    bat_name=$(mode_to_name "$bat_mode")
    
    # Check if on AC or battery
    local power_source="ac"
    if [[ -f /sys/class/power_supply/AC0/online ]]; then
        if [[ $(cat /sys/class/power_supply/AC0/online) == "0" ]]; then
            power_source="bat"
        fi
    fi
    
    local current_mode current_name
    if [[ "$power_source" == "ac" ]]; then
        current_mode=$ac_mode
        current_name=$ac_name
    else
        current_mode=$bat_mode
        current_name=$bat_name
    fi
    
    local display
    display=$(mode_to_display "$current_mode")
    
    # Output Waybar-style JSON
    echo "{\"text\": \"$display\", \"alt\": \"$current_name\"}"
}

toggle_power() {
    # Check if on AC or battery
    local power_source="ac"
    if [[ -f /sys/class/power_supply/AC0/online ]]; then
        if [[ $(cat /sys/class/power_supply/AC0/online) == "0" ]]; then
            power_source="bat"
        fi
    fi
    
    local current_mode
    current_mode=$(get_power_mode "$power_source")
    
    if [[ "$current_mode" == "error" ]]; then
        notify-send -u critical "Razer Power" "Failed to read power mode. Is daemon running?"
        return 1
    fi
    
    # Cycle: 0 -> 1 -> 2 -> 3 -> 0 (skip 4=custom which requires extra params)
    local next_mode
    case "$current_mode" in
        0) next_mode=1 ;;  # Balanced -> Gaming
        1) next_mode=2 ;;  # Gaming -> Creator
        2) next_mode=3 ;;  # Creator -> Silent
        3) next_mode=0 ;;  # Silent -> Balanced
        *) next_mode=0 ;;  # Unknown/Custom -> Balanced
    esac
    
    razer-cli write power "$power_source" "$next_mode"
    
    local new_name
    new_name=$(mode_to_display "$next_mode")
    notify-send "Razer Power" "Power mode: $new_name"
}

listen_mode() {
    local last_output=""
    local last_mode=""
    local current_output
    local current_mode
    local current_display
    
    # Continuous loop with polling
    while true; do
        current_output=$(output_json)
        
        # Only output when state changes
        if [[ "$current_output" != "$last_output" ]]; then
            echo "$current_output"
            
            # Extract mode from JSON and notify on external changes
            current_mode=$(echo "$current_output" | grep -oP '"alt": "\K[^"]+')
            current_display=$(echo "$current_output" | grep -oP '"text": "\K[^"]+')
            
            # Notify if this isn't the first read and mode changed
            if [[ -n "$last_mode" ]] && [[ "$current_mode" != "$last_mode" ]]; then
                notify-send "Razer Power" "Power mode changed: $current_display"
            fi
            
            last_output="$current_output"
            last_mode="$current_mode"
        fi
        
        # Poll every 5 seconds
        sleep 5
    done
}

case "${1:-}" in
    toggle)
        toggle_power
        ;;
    listen)
        listen_mode
        ;;
    *)
        output_json
        ;;
esac
