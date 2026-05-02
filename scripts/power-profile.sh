#!/bin/sh
# Power profile switcher via rofi (uses power-profiles-daemon)
# Usage:
#   power-profile.sh                  - rofi menu
#   power-profile.sh <profile>        - set directly (power-saver|balanced|performance)

set -e

if ! command -v powerprofilesctl >/dev/null 2>&1; then
    notify-send -i battery "Power Profile" "powerprofilesctl not found - install power-profiles-daemon" 2>/dev/null
    echo "✗ powerprofilesctl not found" >&2
    exit 1
fi

# Direct set from arg
if [ -n "${1:-}" ]; then
    powerprofilesctl set "$1"
    notify-send -i battery "Power Profile" "→ $1" 2>/dev/null
    echo "✓ Set to $1"
    exit 0
fi

# Interactive rofi menu
if ! command -v rofi >/dev/null 2>&1; then
    echo "rofi not installed - pass profile as arg, e.g.: $0 power-saver" >&2
    exit 1
fi

CURRENT=$(powerprofilesctl get 2>/dev/null)
PROFILES=$(powerprofilesctl list 2>/dev/null | awk '
    /^\* / {gsub(":", "", $2); print $2; next}
    /^ *[a-z-]+:/ {gsub(":", "", $1); print $1}
')

# Build menu (mark current with asterisk)
MENU=""
for p in $PROFILES; do
    if [ "$p" = "$CURRENT" ]; then
        MENU="${MENU}${p} (current)\n"
    else
        MENU="${MENU}${p}\n"
    fi
done

CHOICE=$(printf "$MENU" | rofi -dmenu -i -p "Power profile [$CURRENT]")
[ -z "$CHOICE" ] && exit 0

PROFILE=$(echo "$CHOICE" | awk '{print $1}')
[ -z "$PROFILE" ] && exit 0
[ "$PROFILE" = "$CURRENT" ] && exit 0

powerprofilesctl set "$PROFILE"
notify-send -i battery "Power Profile" "→ $PROFILE" 2>/dev/null
echo "✓ Set to $PROFILE"
