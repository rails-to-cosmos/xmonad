#!/bin/bash
# One-time setup for KMonad: permissions, uinput module, group membership.
# Run once with sudo after installing kmonad.
set -euo pipefail

echo "=== KMonad Setup ==="

# 1. Install kmonad if not present
if ! command -v kmonad >/dev/null 2>&1; then
    echo "Installing kmonad..."
    sudo pacman -S --needed --noconfirm kmonad
fi

# 2. Ensure 'uinput' group exists
if ! getent group uinput >/dev/null 2>&1; then
    sudo groupadd uinput
    echo "✓ Created 'uinput' group"
fi

# 3. Add user to input + uinput groups
sudo usermod -aG input,uinput "$USER"
echo "✓ Added $USER to input,uinput groups"

# 4. udev rule: allow uinput group to write to /dev/uinput
sudo tee /etc/udev/rules.d/90-kmonad.rules > /dev/null << 'EOF'
KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
EOF
echo "✓ Created udev rule /etc/udev/rules.d/90-kmonad.rules"

# 5. Load uinput module now and on boot
sudo modprobe uinput
if ! grep -q '^uinput$' /etc/modules-load.d/*.conf 2>/dev/null; then
    echo "uinput" | sudo tee /etc/modules-load.d/kmonad.conf > /dev/null
fi
echo "✓ uinput module loaded and set to load on boot"

# 6. Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# 7. Disable keyd if enabled (conflicts with KMonad)
if systemctl is-enabled keyd >/dev/null 2>&1; then
    sudo systemctl disable --now keyd
    echo "✓ Disabled keyd (would conflict with KMonad)"
fi

echo ""
echo "=== Done ==="
echo ""
echo "IMPORTANT: Log out and back in for group changes to take effect."
echo "Then KMonad will start automatically via xmonad startup hook."
echo ""
echo "Test manually with:"
echo "  kmonad ~/.config/kmonad/framework16.kbd"
