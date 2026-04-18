#!/bin/sh
# Write xmobar color palette for the specified theme and restart xmobar if it changed.
# Usage: theme-sync.sh [light|dark]

palette=/tmp/xmobar-theme
prev=/tmp/xmobar-theme-variant
theme_conf=~/.config/xmobar/theme.conf

variant="${1:-dark}"

# Check if theme actually changed
[ -f "$prev" ] && old=$(cat "$prev") || old=""
echo "$variant" > "$prev"

if [ "$variant" = "light" ]; then
    cat > "$palette" <<'EOF'
BG="#FFFFFF"
FG="#000000"
BORDER="#C0C5CF"
ACCENT="#4CB5F5"
GOOD="#B6E63E"
WARN="#FFCC00"
ERR="#E74C3C"
DIM="#C0C5CF"
MID="#7F8C8D"
DARK="#BDC3C7"
FROST="#000000"
NORMAL="#39393D"
EOF
else
    cat > "$palette" <<'EOF'
BG="#000000"
FG="#FFFFFF"
BORDER="#21252B"
ACCENT="#4CB5F5"
GOOD="#B6E63E"
WARN="#FFCC00"
ERR="#E74C3C"
DIM="#525254"
MID="#C0C5CF"
DARK="#39393D"
FROST="#D0E1F9"
NORMAL="#D0E1F9"
EOF
fi

# Write theme overrides and rebuild xmobarrc
cp "$palette" "$theme_conf"

# Restart xmobar if theme changed
if [ "$old" != "$variant" ] && [ -n "$old" ]; then
    ~/.config/xmobar/build.sh
    xmonad --restart
fi
