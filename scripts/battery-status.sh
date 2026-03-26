#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { ERR="#E74C3C"; WARN="#FFCC00"; GOOD="#B6E63E"; }

bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[ -z "$bat" ] && exit 0

cap=$(cat "$bat/capacity" 2>/dev/null || echo 0)
status=$(cat "$bat/status" 2>/dev/null)

case "$status" in
    Charging)    icon=$(printf '\xef\x83\xa7') ;;
    Discharging) icon=$(printf '\xef\x89\x80') ;;
    Full)        icon=$(printf '\xef\x87\xa6') ;;
    *)           icon=$(printf '\xef\x87\xa6') ;;
esac

if [ "$cap" -le 20 ]; then
    color="$ERR"
elif [ "$cap" -le 80 ]; then
    color="$WARN"
else
    color="$GOOD"
fi

echo "<fn=1><fc=$color>$icon</fc></fn> ${cap}%"
