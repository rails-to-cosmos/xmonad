#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { DIM="#525254"; MID="#C0C5CF"; FROST="#D0E1F9"; WARN="#FFCC00"; }
cache=/tmp/xmobar-backlight
if [ ! -f "$cache" ]; then
    bl=$(ls -d /sys/class/backlight/*/ 2>/dev/null | head -1)
    [ -z "$bl" ] && exit 0
    echo "$bl" > "$cache"
fi
bl=$(cat "$cache")

b=$(( $(cat "$bl/brightness") * 100 / $(cat "$bl/max_brightness") ))

if [ $b -lt 25 ]; then
    c="$DIM"
elif [ $b -lt 50 ]; then
    c="$MID"
elif [ $b -lt 75 ]; then
    c="$FROST"
else
    c="$WARN"
fi

printf '<fn=1><fc=%s>\xef\x83\xab</fc></fn>' "$c"
