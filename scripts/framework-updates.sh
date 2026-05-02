#!/bin/sh
# Framework laptop firmware update checker for xmobar
# Detects Framework hardware, checks fwupd for updates, outputs xmobar-formatted status.
# Caches results for 1 hour to avoid expensive checks.

# 1. Only run on Framework laptops
sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
case "$sys_vendor" in
    Framework*) ;;
    *) exit 0 ;;
esac

# 2. Need fwupdmgr
command -v fwupdmgr >/dev/null 2>&1 || exit 0

# 3. Theme colors (defaults; override from theme file if present)
WARN="#FFCC00"
DIM="#525254"
[ -f /tmp/xmobar-theme ] && . /tmp/xmobar-theme

# 4. Cache configuration
CACHE=/tmp/framework-updates
MAX_AGE=3600  # 1 hour
NOW=$(date +%s)

# 5. Refresh cache if missing or stale
needs_refresh=true
if [ -f "$CACHE" ]; then
    age=$((NOW - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0)))
    [ "$age" -lt "$MAX_AGE" ] && needs_refresh=false
fi

if [ "$needs_refresh" = true ]; then
    if fwupdmgr get-updates --json 2>/dev/null > "${CACHE}.tmp"; then
        mv "${CACHE}.tmp" "$CACHE" 2>/dev/null
    else
        echo '{}' > "$CACHE"
        rm -f "${CACHE}.tmp"
    fi
fi

# 6. Count available updates from JSON output (counts every "DeviceId" key)
count=$(grep -o '"DeviceId"' "$CACHE" 2>/dev/null | wc -l)
[ -z "$count" ] && count=0

# 7. Output (only when updates available — widget hides itself otherwise)
if [ "$count" -gt 0 ]; then
    # \xef\x80\x99 = Font Awesome download icon
    # Click to refresh cache by removing it (next run will re-fetch)
    printf '<action=`rm -f /tmp/framework-updates` button=3><fn=1><fc=%s>\xef\x80\x99</fc></fn> %d</action>' "$WARN" "$count"
fi
