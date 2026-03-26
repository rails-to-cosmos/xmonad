#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { GOOD="#B6E63E"; WARN="#FFCC00"; ERR="#E74C3C"; DIM="#525254"; }
icon=$(printf '\xee\x98\xb2')
s=$(cat /tmp/emacs-status 2>/dev/null)
case "$s" in
    ready)    c="$GOOD" ;;
    starting) c="$WARN" ;;
    error)    c="$ERR" ;;
    *)        c="$DIM" ;;
esac
printf '<fn=1><fc=%s>%s</fc></fn>' "$c" "$icon"
