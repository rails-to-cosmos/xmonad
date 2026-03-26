#!/bin/sh
cache=/tmp/xmobar-backlight
if [ ! -f "$cache" ]; then
    bl=$(ls -d /sys/class/backlight/*/ 2>/dev/null | head -1)
    [ -z "$bl" ] && exit 0
    echo "$bl" > "$cache"
fi
bl=$(cat "$cache")

b=$(( $(cat "$bl/brightness") * 100 / $(cat "$bl/max_brightness") ))

if [ $b -lt 25 ]; then
    c='#525254'
elif [ $b -lt 50 ]; then
    c='#C0C5CF'
elif [ $b -lt 75 ]; then
    c='#D0E1F9'
else
    c='#FFCC00'
fi

printf '<fn=1><fc=%s>\xef\x83\xab</fc></fn>' "$c"
