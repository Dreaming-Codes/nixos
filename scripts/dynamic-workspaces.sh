#!/bin/sh
# Dynamic workspace configuration listener for laptop based on external monitor state
# Listens to Hyprland IPC events and reconfigures workspaces when monitors change
# When DP-2 is connected: workspaces 1-10 go to DP-2, F1-F10 stay on eDP-1
# When DP-2 is disconnected: all workspaces revert to eDP-1

configure_workspaces() {
    # Hyprland 0.53.x bug: mergeWorkspaceRules uses "first-writer-wins" for the
    # monitor field, so keyword workspace can't overwrite an existing monitor binding.
    # Workaround: reload config to clear all rules, then re-apply with correct monitors.
    hyprctl reload config-only

    # Check if DP-2 monitor is connected
    if hyprctl monitors | grep -q "DP-2"; then
        echo "DP-2 connected - binding 1-10 to DP-2, F1-F10 to eDP-1"

        hyprctl keyword workspace "1, default:true, monitor:DP-2"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "$i, monitor:DP-2"
        done
        hyprctl keyword workspace "name:F1, default:true, monitor:eDP-1"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "name:F$i, monitor:eDP-1"
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "$i DP-2" 2>/dev/null
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "name:F$i eDP-1" 2>/dev/null
        done
        # Switch to F2 and then back to F1 to refresh ashell displayed name
        hyprctl dispatch workspace name:F2
        hyprctl dispatch workspace name:F1
    else
        echo "DP-2 disconnected - binding all workspaces to eDP-1"

        current_workspace=$(hyprctl activeworkspace -j | jq -r '.id')

        hyprctl keyword workspace "1, default:true, monitor:eDP-1"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "$i, monitor:eDP-1"
        done
        hyprctl keyword workspace "name:F1, default:true, monitor:eDP-1"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "name:F$i, monitor:eDP-1"
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "$i eDP-1" 2>/dev/null
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "name:F$i eDP-1" 2>/dev/null
        done

        hyprctl dispatch workspace "$current_workspace"
    fi
}

handle_event() {
    case $1 in
        monitoraddedv2*|monitorremovedv2*)
            # Ignore v2 duplicates, we already handle the base events
            ;;
        monitoradded*|monitorremoved*)
            echo "Event received: $1"
            sleep 1
            configure_workspaces
            ;;
    esac
}

# Initial configuration on startup
echo "dynamic-workspaces daemon starting"
configure_workspaces

# Listen for IPC events
echo "Listening for monitor events..."
socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    handle_event "$line"
done
