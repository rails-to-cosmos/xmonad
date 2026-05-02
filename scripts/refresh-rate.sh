#!/bin/sh
# Refresh rate switcher via rofi (dmenu-mode) for active display(s).
# Lower rates save 1-2W on battery; higher rates feel smoother on AC.
# Usage:
#   refresh-rate.sh           - rofi menu (interactive)
#   refresh-rate.sh <rate>    - set rate directly (e.g., 60)

set -e

# Pick the primary connected output (eDP-* preferred for laptop panel)
OUTPUT=$(xrandr --query | awk '/ connected/ && /primary/ {print $1; exit}')
if [ -z "$OUTPUT" ]; then
    OUTPUT=$(xrandr --query | awk '/ connected/ {print $1; exit}')
fi

if [ -z "$OUTPUT" ]; then
    notify-send "Refresh Rate" "No connected output found" 2>/dev/null
    echo "✗ No connected output" >&2
    exit 1
fi

# Available rates for the current resolution (parses xrandr output)
# Modes line example: "  2560x1600    165.00*+  60.00     48.00     ..."
RATES=$(xrandr --query | awk -v out="$OUTPUT" '
    $1 == out {found=1; next}
    found && /^[A-Z]/ {found=0}
    found && /^ +[0-9]+x[0-9]+/ && current_mode=="" {current_mode=$1}
    found && $1 == current_mode {
        for (i=2; i<=NF; i++) {
            r = $i
            gsub(/[*+]/, "", r)
            if (r ~ /^[0-9]+\.[0-9]+$/) print int(r)
        }
        exit
    }
' | sort -urn)

if [ -z "$RATES" ]; then
    # Fallback: extract any rate from xrandr -q
    RATES=$(xrandr --query | grep -oE '[0-9]+\.[0-9]+' | awk '{print int($0)}' | sort -urn | head -10)
fi

# Current active resolution+rate for this output (the line with * marks active mode)
RES=$(xrandr --query | awk -v out="$OUTPUT" '
    $1 == out {found=1; next}
    found && /^[A-Z]/ {found=0}
    found && /\*/ {print $1; exit}
')
CURRENT=$(xrandr --query | awk -v out="$OUTPUT" '
    $1 == out {found=1; next}
    found && /\*/ {
        for (i=2; i<=NF; i++) if ($i ~ /\*/) {
            r = $i; gsub(/[*+]/, "", r); print int(r); exit
        }
    }
')

# Direct rate from arg
if [ -n "${1:-}" ]; then
    xrandr --output "$OUTPUT" --mode "$RES" --rate "$1"
    notify-send -i video-display "Refresh Rate" "$OUTPUT → $1 Hz @ $RES" 2>/dev/null
    exit 0
fi

# Interactive rofi menu
if ! command -v rofi >/dev/null 2>&1; then
    echo "rofi not installed - pass rate as arg, e.g.: $0 60" >&2
    exit 1
fi

# Format menu items with current rate marked
MENU=""
for rate in $RATES; do
    if [ "$rate" = "$CURRENT" ]; then
        MENU="${MENU}${rate} Hz (current)\n"
    else
        MENU="${MENU}${rate} Hz\n"
    fi
done

CHOICE=$(printf "$MENU" | rofi -dmenu -i -p "Refresh rate ($OUTPUT)")
[ -z "$CHOICE" ] && exit 0

# Extract numeric rate from choice
RATE=$(echo "$CHOICE" | awk '{print $1}')
[ -z "$RATE" ] && exit 0

xrandr --output "$OUTPUT" --mode "$RES" --rate "$RATE"
notify-send -i video-display "Refresh Rate" "$OUTPUT → $RATE Hz" 2>/dev/null
echo "✓ $OUTPUT set to $RATE Hz"
