#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { GOOD="#B6E63E"; DIM="#525254"; }
icon=$(printf '\xf3\xb0\x96\x82')
iface=$(ip -o link show type wireguard 2>/dev/null | awk -F: '{print $2}' | tr -d ' ' | head -1)
if [ -n "$iface" ]; then
    printf '<fn=1><fc=%s>%s</fc></fn> <fc=%s>%s</fc>' "$GOOD" "$icon" "$GOOD" "$iface"
else
    printf '<fn=1><fc=%s>%s</fc></fn> <fc=%s>off</fc>' "$DIM" "$icon" "$DIM"
fi
