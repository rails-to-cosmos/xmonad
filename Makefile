.PHONY: install reload restart recompile build-scripts clean

install:
	./scripts/install.sh
	./scripts/install-dmenu.sh

# Rebuild all script binaries (xmobar-status.hs, etc.)
build-scripts:
	./scripts/build-xmobar-status.sh ./scripts/build-xmobar-status

# Recompile xmonad (also triggers build-scripts via build.sh)
recompile:
	xmonad --recompile

# Recompile + restart in one shot
reload: recompile
	xmonad --restart

# Just restart (no recompile)
restart:
	xmonad --restart

# Remove build artifacts
clean:
	rm -rf ./build-x86_64-linux
	rm -rf ./scripts/build-xmobar-status
	rm -f  ./scripts/xmobar-status
	rm -f  ./xmonad
	rm -f  ./xmonad-x86_64-linux
