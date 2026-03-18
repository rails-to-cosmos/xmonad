#!/bin/sh
mkdir -p "$(dirname "$1")"
exec /usr/bin/ghc --make xmonad.hs -i -ilib -fforce-recomp -main-is main -dynamic -v0 -outputdir "$(dirname "$1")/build-x86_64-linux" -o "$1"
