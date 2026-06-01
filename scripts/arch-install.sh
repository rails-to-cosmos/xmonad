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


# Audio (for volume widget)
sudo pacman -S --needed --noconfirm \
    alsa-utils

# Brightness control (powers the XF86MonBrightness keybinds)
sudo pacman -S --needed --noconfirm \
    brightnessctl

# Polkit auth agent (enables GUI password prompts for pkexec, e.g., from rofi keybinds)
sudo pacman -S --needed --noconfirm \
    polkit-gnome

# Keyboard remapping (KMonad: Caps→Ctrl/Esc tap-hold, layers, etc.)
sudo pacman -S --needed --noconfirm \
    kmonad
./scripts/setup-kmonad.sh

# Power profile daemon (auto AC/battery profile switching, integrates with desktop)
sudo pacman -S --needed --noconfirm \
    power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Email (mu4e + IMAP sync)
sudo pacman -S --needed --noconfirm \
    isync
paru -S --needed --noconfirm \
    mu

# Keyboard event/keysym debug (xev, useful for troubleshooting keybinds and remaps)
sudo pacman -S --needed --noconfirm \
    xorg-xev

# Display auto-configuration (saves/restores xrandr profiles based on connected displays)
sudo pacman -S --needed --noconfirm \
    autorandr
systemctl --user enable --now autorandr.service 2>/dev/null || true

# Document conversion + clipboard (powers web2org.sh: HTML/PDF/MD -> org/latex etc.)
sudo pacman -S --needed --noconfirm \
    pandoc-cli \
    xclip

# Web-capture extras (powers web2org.d handlers: youtube + arxiv + pdf)
# All previously system-installed dependencies are now self-contained uv scripts
# in this repo's scripts/ directory (managed by `uv run --script` via PEP 723):
#   scripts/yt-dlp     : YouTube metadata + auto-subs + audio extraction
#   scripts/jq         : JSON queries (bundles libjq via PyPI `jq`)
#   scripts/xmllint    : XPath queries (lxml wheel bundles libxml2)
#   scripts/pdftotext  : PDF → text (pdfminer.six, pure Python)
#   scripts/pdfinfo    : PDF metadata (pypdf, pure Python)
# web2org.sh prepends scripts/ to PATH so handlers find these by name.
# Only `uv` is required system-wide (already installed by default on CachyOS).
# Optional (install manually if you want whisper transcription fallback for YT):
#   pacman -S whisper.cpp     OR    pipx install openai-whisper
sudo pacman -S --needed --noconfirm uv

# LaTeX / pdflatex (needed for pandoc -> PDF and standalone LaTeX builds)
# Installs the full texlive group (~3-5 GB) so all packages, fonts, and engines are available
sudo pacman -S --needed --noconfirm texlive

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
