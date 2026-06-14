#!/bin/sh
# Singleton supervisor that keeps the xmobar status daemon running.
#
# An flock on a lockfile makes this a singleton: the startupHook can launch it
# unconditionally on every xmonad (re)start — a second instance fails the lock
# and exits, so the original keeps running and holding the lock. (A pgrep guard
# can't be used: its own `sh -c` argv contains the launch path, so it would
# always match itself.) The loop respawns the daemon a couple of seconds after
# it exits; to pick up a freshly-built binary, the startupHook kills the daemon
# child after a rebuild and this loop respawns it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/xmobar-statusd.lock"

exec 9>"$LOCK"
flock -n 9 || exit 0          # another supervisor already owns the lock

while true; do
    "$HERE/xmobar-status" daemon
    sleep 2
done
