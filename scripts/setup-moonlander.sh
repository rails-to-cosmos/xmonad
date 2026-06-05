#!/bin/bash
# Udev rules for ZSA Moonlander (and other ZSA boards) so keymapp can open the
# hidraw device for live training + flashing without root.
#
# Uses systemd-logind `uaccess` (grants the active local-session user access),
# so no `plugdev` group membership is required.
#
# Run once:  sudo bash ~/.config/xmonad/scripts/setup-moonlander.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo $0"
    exit 1
fi

RULES=/etc/udev/rules.d/50-zsa.rules

tee "$RULES" > /dev/null <<'EOF'
# ZSA keyboards (Moonlander, Voyager, ErgoDox EZ, Planck EZ) — keymapp / Oryx.
# Access granted to the active local-session user via systemd-logind uaccess.

# Normal operation + keymapp live training (vendor 3297, all products)
KERNEL=="hidraw*", ATTRS{idVendor}=="3297", TAG+="uaccess"
SUBSYSTEM=="usb",  ATTRS{idVendor}=="3297", TAG+="uaccess"

# STM32 DFU bootloader (Moonlander / Planck EZ flashing)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess", SYMLINK+="stm32_dfu"
EOF

echo "✓ wrote $RULES"

udevadm control --reload-rules
udevadm trigger --subsystem-match=hidraw --subsystem-match=usb --action=add
echo "✓ reloaded udev rules and re-triggered hidraw/usb"

echo ""
echo "If keymapp still says 'Permission denied', unplug and replug the Moonlander"
echo "(uaccess ACLs are applied on device 'add'). Then verify:"
echo "  getfacl /dev/hidraw0   # should show 'user:akatovda:rw-'"
