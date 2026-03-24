#!/bin/sh
cache=/tmp/xmobar-cputemp-hwmon
if [ ! -f "$cache" ]; then
    for n in coretemp k10temp; do
        f=$(grep -rl "^${n}$" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1)
        [ -n "$f" ] && break
    done
    d=${f%/name}
    [ -z "$d" ] && exit 0
    echo "$d" > "$cache"
fi
d=$(cat "$cache")
echo $(( $(cat "$d/temp1_input") / 1000 ))C
