#!/bin/sh
mkdir -p "$(dirname "$1")"

# Compile xmobar-status widgets
SCRIPTS_DIR="$(dirname "$0")"
ghc -O2 -dynamic -v0 \
    -outputdir "$(dirname "$1")/build-xmobar-status" \
    -o "$SCRIPTS_DIR/xmobar-status" \
    "$SCRIPTS_DIR/xmobar-status.hs" 2>/dev/null

exec /usr/bin/ghc --make xmonad.hs -i -ilib -fforce-recomp -main-is main -dynamic -v0 -outputdir "$(dirname "$1")/build-x86_64-linux" -o "$1"
