#!/bin/bash
# Kernel-level Caps Lock → Left Ctrl remapping for Framework 16
# Bypasses X11 / keyd / autorepeat issues by remapping at the input layer
set -euo pipefail

HWDB_FILE="/etc/udev/hwdb.d/10-framework-keyboard.hwdb"

sudo tee "$HWDB_FILE" > /dev/null << 'EOF'
# Framework Laptop 16 Keyboard Module - ANSI (32ac:0012)
evdev:input:b0003v32ACp0012*
 KEYBOARD_KEY_70039=leftctrl

# Framework Laptop 16 Numpad Module (32ac:0014)
evdev:input:b0003v32ACp0014*
 KEYBOARD_KEY_70039=leftctrl
EOF

echo "Created $HWDB_FILE"
echo "Updating hwdb..."
sudo systemd-hwdb update

echo "Triggering udev for input devices..."
sudo udevadm trigger --subsystem-match=input --action=change

echo ""
echo "✓ Kernel-level Caps→Ctrl remapping installed"
echo ""
echo "Next steps:"
echo "  1. Disable conflicting remappings:"
echo "     sudo systemctl disable --now keyd"
echo "  2. Remove caps:ctrl_modifier from xmonad.hs setxkbmap call"
echo "  3. Logout/login (or reboot) to fully apply"
echo ""
echo "Test with: sudo showkey"
echo "  Press CapsLock - should now show keycode 29 (Left Ctrl) instead of 58"
