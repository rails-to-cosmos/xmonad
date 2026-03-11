#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR=$(mktemp -d)
PATCH="$SCRIPT_DIR/dmenu/dmenu-lineheight-5.2.diff"

trap 'rm -rf "$BUILD_DIR"' EXIT

git clone https://git.suckless.org/dmenu "$BUILD_DIR/dmenu"
cd "$BUILD_DIR/dmenu"
git apply "$PATCH"
sudo make clean install
