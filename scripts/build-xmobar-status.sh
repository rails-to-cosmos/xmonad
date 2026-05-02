#!/bin/sh
# Compile xmobar-status. Skips if the binary is newer than the source.
set -e
SRC="$(dirname "$0")/xmobar-status.hs"
BIN="$(dirname "$0")/xmobar-status"
OUT="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/xmonad/build-xmobar-status}"

# Only rebuild if source is newer than binary (or binary missing)
if [ -f "$BIN" ] && [ "$BIN" -nt "$SRC" ]; then
    exit 0
fi

mkdir -p "$OUT"
ghc -O2 -dynamic -v0 -outputdir "$OUT" -o "$BIN" "$SRC"
