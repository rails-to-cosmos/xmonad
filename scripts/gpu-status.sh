#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { DIM="#525254"; }
cache=/tmp/gpu-cards
if [ ! -f "$cache" ]; then
    for card in /sys/class/drm/card[0-9]*; do
        [ -f "$card/device/gpu_busy_percent" ] || continue
        name=$(basename "$card")
        pci=$(readlink "$card/device" | grep -oP '[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]')
        desc=$(lspci -s "$pci" 2>/dev/null)
        # Try "Chip [Product Name]" format first, fall back to last "] Chip"
        label=$(echo "$desc" | grep -oP '\] \K[^[]+(?= \[)' | head -1)
        [ -z "$label" ] && label=$(echo "$desc" | grep -oP '\] \K[^\[(]+' | tail -1)
        label=$(echo "$label" | sed 's/ *(rev .*//;s/ *$//')
        [ -z "$label" ] && label="$name"
        echo "$name $label" >> "$cache"
    done
fi

[ ! -f "$cache" ] && exit 0

parts=""
while read -r name label; do
    sys="/sys/class/drm/$name/device"
    state=$(cat "$sys/power/runtime_status" 2>/dev/null)
    if [ "$state" = "active" ]; then
        pct=$(cat "$sys/gpu_busy_percent" 2>/dev/null || echo "?")
        parts="$parts${parts:+  }$label ${pct}%"
    else
        parts="$parts${parts:+  }$label <fc=$DIM>off</fc>"
    fi
done < "$cache"

[ -n "$parts" ] && printf '<fn=1>\xf3\xb0\xba\xa8</fn> %s | ' "$parts"
