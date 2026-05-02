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

# Audio (for volume widget)
sudo pacman -S --needed --noconfirm \
    alsa-utils

# Brightness control (powers the XF86MonBrightness keybinds)
sudo pacman -S --needed --noconfirm \
    brightnessctl

# Polkit auth agent (enables GUI password prompts for pkexec, e.g., from rofi keybinds)
sudo pacman -S --needed --noconfirm \
    polkit-gnome

# Display auto-configuration (saves/restores xrandr profiles based on connected displays)
sudo pacman -S --needed --noconfirm \
    autorandr
systemctl --user enable --now autorandr.service 2>/dev/null || true

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
