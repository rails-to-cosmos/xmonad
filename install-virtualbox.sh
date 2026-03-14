#!/bin/sh
set -e

echo "Installing VirtualBox and DKMS modules..."
sudo pacman -S --needed virtualbox virtualbox-host-dkms

echo "Loading kernel module..."
sudo modprobe vboxdrv

echo "Adding $USER to vboxusers group..."
sudo usermod -aG vboxusers "$USER"

echo "Installing extension pack..."
if command -v yay >/dev/null 2>&1; then
    yay -S --needed virtualbox-ext-oracle
elif command -v paru >/dev/null 2>&1; then
    paru -S --needed virtualbox-ext-oracle
else
    echo "No AUR helper found. Install virtualbox-ext-oracle manually from AUR."
    exit 1
fi

echo "Done. Log out and back in for group changes to take effect."
