#!/bin/sh
# Dynamic workspace configuration listener for laptop based on external monitor state
# Listens to Hyprland IPC events and reconfigures workspaces when monitors change
#
# When DP-2 is connected: workspaces 1-10 go to DP-2 (primary), F1-F10 stay on eDP-1
# When another external monitor is connected: workspaces 1-10 stay on eDP-1 (primary), F1-F10 go to external
# When no external monitor: all workspaces revert to eDP-1

INTERNAL="eDP-1"
PRIMARY_EXTERNAL="DP-2"

get_external_monitor() {
    hyprctl monitors -j | jq -r --arg internal "$INTERNAL" \
        '[.[] | select(.name != $internal)][0].name // empty'
}

configure_workspaces() {
    # Hyprland 0.53.x bug: mergeWorkspaceRules uses "first-writer-wins" for the
    # monitor field, so keyword workspace can't overwrite an existing monitor binding.
    # Workaround: reload config to clear all rules, then re-apply with correct monitors.
    hyprctl reload config-only

    external=$(get_external_monitor)

    if [ -n "$external" ]; then
        if [ "$external" = "$PRIMARY_EXTERNAL" ]; then
            primary="$external"
            secondary="$INTERNAL"
        else
            primary="$INTERNAL"
            secondary="$external"
        fi

        echo "External monitor '$external' connected - primary: $primary, secondary: $secondary"

        hyprctl keyword workspace "1, default:true, monitor:$primary"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "$i, monitor:$primary"
        done
        hyprctl keyword workspace "name:F1, default:true, monitor:$secondary"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "name:F$i, monitor:$secondary"
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "$i $primary" 2>/dev/null
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "name:F$i $secondary" 2>/dev/null
        done
        # Switch to F2 and then back to F1 to refresh ashell displayed name
        hyprctl dispatch workspace name:F2
        hyprctl dispatch workspace name:F1
    else
        echo "No external monitor - binding all workspaces to $INTERNAL"

        current_workspace=$(hyprctl activeworkspace -j | jq -r '.id')

        hyprctl keyword workspace "1, default:true, monitor:$INTERNAL"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "$i, monitor:$INTERNAL"
        done
        hyprctl keyword workspace "name:F1, default:true, monitor:$INTERNAL"
        for i in 2 3 4 5 6 7 8 9 10; do
            hyprctl keyword workspace "name:F$i, monitor:$INTERNAL"
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "$i $INTERNAL" 2>/dev/null
        done
        for i in 1 2 3 4 5 6 7 8 9 10; do
            hyprctl dispatch moveworkspacetomonitor "name:F$i $INTERNAL" 2>/dev/null
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
