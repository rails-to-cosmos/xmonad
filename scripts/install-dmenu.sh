#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR=$(mktemp -d)
PATCH="$REPO_DIR/dmenu/dmenu-lineheight-5.2.diff"

if [ ! -f "$PATCH" ]; then
    echo "Patch not found: $PATCH"
    echo "Skipping patched dmenu build (stock dmenu will be used)."
    exit 0
fi

trap 'rm -rf "$BUILD_DIR"' EXIT

git clone https://git.suckless.org/dmenu "$BUILD_DIR/dmenu"
cd "$BUILD_DIR/dmenu"
git apply "$PATCH"
sudo make clean install
