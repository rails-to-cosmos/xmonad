#!/bin/sh
# Turn off Caps Lock if currently engaged.
# Useful in xmonad startup so a stuck Caps Lock LED gets cleared on every restart.

if xset q 2>/dev/null | grep -qE "Caps Lock:\s*on"; then
    xdotool key Caps_Lock
fi
