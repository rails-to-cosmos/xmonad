#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { GOOD="#B6E63E"; DIM="#525254"; }
iface=$(ip -o link show type wireguard 2>/dev/null | awk -F: '{print $2}' | tr -d ' ' | head -1)
if [ -n "$iface" ]; then
    echo "<fc=$GOOD>$iface</fc>"
else
    echo "<fc=$DIM>off</fc>"
fi
