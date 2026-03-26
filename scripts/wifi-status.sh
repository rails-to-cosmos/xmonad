#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { DIM="#525254"; GOOD="#B6E63E"; ACCENT="#4CB5F5"; NORMAL="#D0E1F9"; }
iface="wlan0"
state="/tmp/wifi-status-$iface"
essid=$(iw dev "$iface" link 2>/dev/null | awk '/SSID:/{print $2}')
[ -z "$essid" ] && echo "<fc=$DIM>disconnected</fc>" && exit 0

rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)

if [ -f "$state" ]; then
    read prev_rx prev_tx < "$state"
    dt=3  # poll interval in seconds
    rx_rate=$(( (rx - prev_rx) / dt ))
    tx_rate=$(( (tx - prev_tx) / dt ))
    # bytes/sec thresholds
    if [ $rx_rate -gt 1000000 ] || [ $tx_rate -gt 1000000 ]; then
        color="$GOOD"    # green: >1MB/s
    elif [ $rx_rate -gt 100000 ] || [ $tx_rate -gt 100000 ]; then
        color="$ACCENT"  # blue: >100KB/s
    elif [ $rx_rate -gt 1000 ] || [ $tx_rate -gt 1000 ]; then
        color="$NORMAL"  # normal: >1KB/s
    else
        color="$DIM"     # dim: idle
    fi
else
    color="$NORMAL"
fi

echo "$rx $tx" > "$state"
echo "<fc=$color>$essid</fc>"
