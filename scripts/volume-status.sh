#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { FG="#FFFFFF"; ERR="#E74C3C"; }
out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
vol=$(echo "$out" | awk '{printf "%d", $2 * 100}')
muted=$(echo "$out" | grep -c MUTED)
if [ "$muted" -eq 1 ]; then
    printf '<fc=%s>[M]</fc>' "$ERR"
else
    printf '%s%%' "$vol"
fi
