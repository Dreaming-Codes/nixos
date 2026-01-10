#!/bin/sh
# Dynamic workspace configuration listener for laptop based on external monitor state
# Listens to Hyprland IPC events and reconfigures workspaces when monitors change
# When DP-2 is connected: workspaces 1-10 go to DP-2, F1-F10 stay on eDP-1
# When DP-2 is disconnected: all workspaces revert to eDP-1

configure_workspaces() {
    # Check if DP-2 monitor is connected
    if hyprctl monitors | grep -q "DP-2"; then
        echo "DP-2 connected - binding 1-10 to DP-2, F1-F10 to eDP-1"
        
        # Save current workspace to refocus later
        current_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
        
        # External monitor connected - bind workspaces 1-10 to DP-2
        hyprctl keyword workspace "1, default:true, monitor:DP-2"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "$i, monitor:DP-2"
        done
        # Bind F1-F10 (workspaces named F1-F10) to eDP-1
        hyprctl keyword workspace "name:F1, default:true, monitor:eDP-1"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "name:F$i, monitor:eDP-1"
        done
        # Move any existing workspaces to their proper monitors
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "$i DP-2" 2>/dev/null
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "name:F$i eDP-1" 2>/dev/null
        done
        # Switch eDP-1 to workspace F1 - go to F2 first to force refresh
        hyprctl dispatch workspace name:F2
        hyprctl dispatch workspace name:F1
        # Refocus the original workspace
        hyprctl dispatch workspace "$current_workspace"
    else
        echo "DP-2 disconnected - binding all workspaces to eDP-1"
        
        # No external monitor - bind all workspaces to eDP-1
        hyprctl keyword workspace "1, default:true, monitor:eDP-1"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "$i, monitor:eDP-1"
        done
        hyprctl keyword workspace "name:F1, default:true, monitor:eDP-1"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "name:F$i, monitor:eDP-1"
        done
        # Move any existing workspaces to eDP-1
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "$i eDP-1" 2>/dev/null
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "name:F$i eDP-1" 2>/dev/null
        done
    fi
}

handle_event() {
    case $1 in
        monitoradded*|monitorremoved*)
            echo "Event received: $1"
            # Small delay to let Hyprland settle
            sleep 0.5
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
