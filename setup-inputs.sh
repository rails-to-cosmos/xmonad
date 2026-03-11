#!/bin/bash
set -euo pipefail

xset r rate 170 50

# Enable natural scrolling on all libinput devices that support it
for id in $(xinput list --id-only 2>/dev/null); do
    if xinput list-props "$id" 2>/dev/null | grep -q "libinput Natural Scrolling Enabled"; then
        xinput set-prop "$id" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
    fi
done
