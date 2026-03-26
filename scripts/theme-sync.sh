#!/bin/sh
# Query Emacs for the active danneskjold theme variant, write a color palette
# for status scripts, and restart xmobar if the theme changed.

palette=/tmp/xmobar-theme
prev=/tmp/xmobar-theme-variant
xmobarrc=~/.config/xmobar/xmobarrc

variant=$(emacsclient -e '(if (custom-theme-enabled-p (quote danneskjold-light)) "light" "dark")' 2>/dev/null | tr -d '"')
[ -z "$variant" ] && variant="dark"

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

# Restart xmobar if theme changed
if [ "$old" != "$variant" ] && [ -n "$old" ]; then
    . "$palette"
    sed -i \
        -e "s/bgColor = \"#[0-9A-Fa-f]*\"/bgColor = \"$BG\"/" \
        -e "s/fgColor = \"#[0-9A-Fa-f]*\"/fgColor = \"$FG\"/" \
        -e "s/borderColor = \"#[0-9A-Fa-f]*\"/borderColor = \"$BORDER\"/" \
        "$xmobarrc"
    killall xmobar
    xmobar "$xmobarrc" &
fi
