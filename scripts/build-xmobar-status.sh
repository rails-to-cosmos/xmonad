#!/bin/sh
# Compile xmobar-status. Skips if the binary is newer than the source.
set -e
SRC="$(dirname "$0")/xmobar-status.hs"
BIN="$(dirname "$0")/xmobar-status"
OUT="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/xmonad/build-xmobar-status}"

FORCE="${FORCE_REBUILD:-0}"

# Rebuild if: forced, binary missing, source newer, or linked libs broken
if [ "$FORCE" != "1" ] && [ -f "$BIN" ] && [ "$BIN" -nt "$SRC" ] && ldd "$BIN" 2>&1 | grep -qv 'not found'; then
    exit 0
fi

mkdir -p "$OUT"
# Use system GHC: pacman-installed haskell-dbus (and friends) are registered there.
/usr/bin/ghc -O2 -dynamic -v0 -outputdir "$OUT" -o "$BIN" "$SRC"
