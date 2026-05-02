#!/bin/bash
set -euo pipefail

echo "Installing packages for XMonad desktop setup (Linux Mint)..."

# Core WM and bar
sudo apt-get update
sudo apt-get install -y \
    xmonad \
    libghc-xmonad-contrib-dev \
    xmobar \
    dmenu

# Alacritty (not in default repos, use PPA)
if ! command -v alacritty >/dev/null 2>&1; then
    sudo add-apt-repository -y ppa:aslatter/ppa
    sudo apt-get update
    sudo apt-get install -y alacritty
fi

# Fonts
sudo apt-get install -y \
    fonts-jetbrains-mono

# System tray
sudo apt-get install -y \
    stalonetray

# Audio (for volume widget)
sudo apt-get install -y \
    alsa-utils

# Brightness control (powers the XF86MonBrightness keybinds)
sudo apt-get install -y \
    brightnessctl

# Polkit auth agent (enables GUI password prompts for pkexec, e.g., from rofi keybinds)
sudo apt-get install -y \
    policykit-1-gnome

# Power profile daemon (auto AC/battery profile switching, integrates with desktop)
sudo apt-get install -y \
    power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Display auto-configuration (saves/restores xrandr profiles based on connected displays)
sudo apt-get install -y \
    autorandr

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
