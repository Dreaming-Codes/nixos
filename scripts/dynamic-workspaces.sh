#!/bin/sh
# Dynamic workspace configuration for laptop based on external monitor state
# When DP-2 is connected: workspaces 1-10 go to DP-2, F1-F10 stay on eDP-1
# When DP-2 is disconnected: all workspaces revert to eDP-1

# Check if DP-2 monitor is connected
if hyprctl monitors | grep -q "DP-2"; then
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
    # Focus the original workspace
    # hyprctl dispatch workspace "$current_workspace"
else
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
