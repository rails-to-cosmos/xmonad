#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "Cannot detect OS: /etc/os-release not found."
    exit 1
fi

case "$ID" in
    arch|endeavouros|manjaro)
        echo "Detected Arch-based system ($PRETTY_NAME)"
        exec "$SCRIPT_DIR/arch-install.sh"
        ;;
    linuxmint|ubuntu|debian)
        echo "Detected Debian-based system ($PRETTY_NAME)"
        exec "$SCRIPT_DIR/mint-install.sh"
        ;;
    *)
        echo "Unsupported distribution: $PRETTY_NAME ($ID)"
        echo "Available install scripts:"
        echo "  $SCRIPT_DIR/arch-install.sh  - Arch Linux and derivatives"
        echo "  $SCRIPT_DIR/mint-install.sh  - Linux Mint, Ubuntu, Debian"
        exit 1
        ;;
esac
