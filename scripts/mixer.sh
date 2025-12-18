#!/usr/bin/env bash

PROC_NAME="mixxc"

if pgrep "$PROC_NAME" > /dev/null; then
    echo "Killing $PROC_NAME"
    pkill "$PROC_NAME"
else
    cursorpos=$(hyprctl cursorpos)
    cursor_x=$(echo "$cursorpos" | awk -F',' '{print $1}' | tr -d ' ')
    cursor_y=$(echo "$cursorpos" | awk -F',' '{print $2}' | tr -d ' ')
    echo "Cursor position: x=$cursor_x y=$cursor_y"

    read rel_x rel_y < <(
        hyprctl monitors | awk -v cx="$cursor_x" -v cy="$cursor_y" '
            /^[[:space:]]*[0-9]+x[0-9]+@/ {
                print "Parsing monitor line: " $0 > "/dev/stderr"
                split($1, res, "x")
                width = res[1]
                split(res[2], tmp, "@")
                height = tmp[1]
                at_idx = index($0, "at ")
                pos = substr($0, at_idx + 3)
                split(pos, coords, "x")
                mon_x = coords[1]
                mon_y = coords[2]
                print "Monitor geometry: width=" width " height=" height " mon_x=" mon_x " mon_y=" mon_y > "/dev/stderr"
                if (cx >= mon_x && cx < mon_x + width && cy >= mon_y && cy < mon_y + height) {
                    print "Match! rel_x=" cx - mon_x " rel_y=" cy - mon_y > "/dev/stderr"
                    print cx - mon_x - 200, cy - mon_y - 35
                    exit
                }
            }
        '
    )

    echo "Relative position: x=$rel_x y=$rel_y"

    if [[ -n "$rel_x" && -n "$rel_y" ]]; then
        mixxc -a top -a left -m "$rel_y" -m "$rel_x" --width 400 &
    else
        echo "Error: Could not determine monitor for cursor."
        exit 1
    fi
fi
