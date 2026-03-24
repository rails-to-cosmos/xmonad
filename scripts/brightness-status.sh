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
    c='#565f89'
elif [ $b -lt 50 ]; then
    c='#888888'
elif [ $b -lt 75 ]; then
    c='#c0caf5'
else
    c='#e0af68'
fi

printf '<fn=1><fc=%s>\xef\x83\xab</fc></fn>' "$c"
