#!/bin/bash
set -euo pipefail

echo "Installing packages for XMonad desktop setup..."

# Core WM and bar
sudo pacman -S --needed --noconfirm \
    xmonad \
    xmonad-contrib \
    xmobar \
    dmenu \
    alacritty

# Fonts
sudo pacman -S --needed --noconfirm \
    ttf-jetbrains-mono \
    ttf-jetbrains-mono-nerd

# System tray
sudo pacman -S --needed --noconfirm \
    stalonetray

# Key remapping (fixes CapsLock on Framework 16 QMK firmware)
sudo pacman -S --needed --noconfirm \
    keyd

# Audio (for volume widget)
sudo pacman -S --needed --noconfirm \
    alsa-utils

# Configure keyd: CapsLock -> Ctrl
sudo mkdir -p /etc/keyd
sudo tee /etc/keyd/default.conf > /dev/null << 'EOF'
[ids]

*

[main]

capslock = layer(control)
EOF

sudo systemctl enable --now keyd

# Natural scrolling for touchpad and mouse
sudo tee /etc/X11/xorg.conf.d/30-natural-scroll.conf > /dev/null << 'EOF'
Section "InputClass"
        Identifier "natural scrolling touchpad"
        MatchIsTouchpad "on"
        Option "NaturalScrolling" "true"
        Option "Tapping" "true"
EndSection

Section "InputClass"
        Identifier "natural scrolling mouse"
        MatchIsPointer "on"
        Option "NaturalScrolling" "true"
EndSection
EOF

echo "Done. Log out and select XMonad as your session to start."
