#!/bin/sh
bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -z "$bat" ] && exit 0

cap=$(cat "$bat/capacity" 2>/dev/null || echo 0)
status=$(cat "$bat/status" 2>/dev/null)

case "$status" in
    Charging)    icon="" ;;
    Discharging) icon="" ;;
    Full)        icon="" ;;
    *)           icon="" ;;
esac

if [ "$cap" -le 20 ]; then
    color="#f7768e"
elif [ "$cap" -le 80 ]; then
    color="#e0af68"
else
    color="#9ece6a"
fi

echo "<fn=1><fc=$color>$icon</fc></fn> ${cap}%"
