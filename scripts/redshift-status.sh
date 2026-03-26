#!/bin/sh
. /tmp/xmobar-theme 2>/dev/null || { WARN="#FFCC00"; ACCENT="#4CB5F5"; DIM="#525254"; }
sun=$(printf '\xef\x86\x85')
moon=$(printf '\xf3\xb0\x96\x94')
period=$(redshift -l 52.37:4.90 -p 2>/dev/null | awk '/Period/{print $2}')
case "$period" in
    Daytime)   printf '<fn=1><fc=%s>%s</fc></fn>' "$WARN" "$sun" ;;
    Night)     printf '<fn=1><fc=%s>%s</fc></fn>' "$ACCENT" "$moon" ;;
    "")        printf '<fc=%s>off</fc>' "$DIM" ;;
    *)         printf '<fn=1><fc=%s>%s</fc></fn>' "$WARN" "$sun" ;;
esac
