#!/bin/sh
# Auto-detect connected keyboards and launch KMonad for each.
# Called from xmonad startup hook via spawnOnce.
#
# - Framework 16 keyboard → uses framework16.kbd (handles firmware Caps→Ctrl bug)
# - Any other keyboard    → uses external.kbd with device path injected
#
# Kills existing KMonad instances on re-run (safe for xmonad --restart).

set -e

CONF_DIR="$HOME/.config/kmonad"
FW16_CONF="$CONF_DIR/framework16.kbd"
EXT_CONF="$CONF_DIR/external.kbd"

command -v kmonad >/dev/null 2>&1 || { echo "kmonad not installed"; exit 1; }

# Kill existing instances
pkill -x kmonad 2>/dev/null || true
sleep 0.3

# Framework 16 keyboard (32ac:0012)
FW16_DEV="/dev/input/by-id/usb-Framework_Laptop_16_Keyboard_Module_-_ANSI_FRAKDKEN0100000000-event-kbd"
if [ -e "$FW16_DEV" ] && [ -f "$FW16_CONF" ]; then
    echo "Starting KMonad for Framework 16 keyboard"
    kmonad "$FW16_CONF" &
fi

# External keyboards: find event-kbd devices that aren't Framework
for dev in /dev/input/by-id/*-event-kbd; do
    [ -e "$dev" ] || continue
    case "$dev" in
        *Framework*) continue ;;  # handled above
    esac

    if [ -f "$EXT_CONF" ]; then
        echo "Starting KMonad for external keyboard: $(basename "$dev")"
        tmp=$(mktemp /tmp/kmonad-ext-XXXXXX.kbd)
        sed "s|__DEVICE__|$dev|" "$EXT_CONF" > "$tmp"
        kmonad "$tmp" &
    fi
done

echo "KMonad started"
