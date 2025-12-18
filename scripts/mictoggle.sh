#!/bin/bash

NOTIFY_ID=42042

# Toggle the Capture switch
amixer set Capture toggle

# Get the new state (on/off)
STATE=$(amixer get Capture | grep -m 1 -o '\[on\]\|\[off\]')

if [ "$STATE" = "[on]" ]; then
    notify-send -r $NOTIFY_ID "Microphone" "Microphone is ON 🎤"
else
    notify-send -r $NOTIFY_ID "Microphone" "Microphone is OFF 🔇"
fi
