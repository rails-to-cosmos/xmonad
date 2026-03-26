#!/bin/sh
iface="wlan0"
state="/tmp/wifi-status-$iface"
essid=$(iw dev "$iface" link 2>/dev/null | awk '/SSID:/{print $2}')
[ -z "$essid" ] && echo "<fc=#525254>disconnected</fc>" && exit 0

rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)

if [ -f "$state" ]; then
    read prev_rx prev_tx < "$state"
    dt=3  # poll interval in seconds
    rx_rate=$(( (rx - prev_rx) / dt ))
    tx_rate=$(( (tx - prev_tx) / dt ))
    # bytes/sec thresholds
    if [ $rx_rate -gt 1000000 ] || [ $tx_rate -gt 1000000 ]; then
        color="#B6E63E"  # green: >1MB/s
    elif [ $rx_rate -gt 100000 ] || [ $tx_rate -gt 100000 ]; then
        color="#4CB5F5"  # blue: >100KB/s
    elif [ $rx_rate -gt 1000 ] || [ $tx_rate -gt 1000 ]; then
        color="#D0E1F9"  # normal: >1KB/s
    else
        color="#525254"  # dim: idle
    fi
else
    color="#D0E1F9"
fi

echo "$rx $tx" > "$state"
echo "<fc=$color>$essid</fc>"
