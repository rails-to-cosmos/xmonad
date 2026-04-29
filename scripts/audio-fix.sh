#!/bin/sh
# Detect broken audio state (only Dummy Output / auto_null available)
# and reset WirePlumber state to recover.

default=$(pactl get-default-sink 2>/dev/null)
sinks=$(pactl list sinks short 2>/dev/null | awk '{print $2}')

# Audio is broken if default sink is the null/auto_null fallback,
# or if no real ALSA/Bluetooth sinks exist.
broken=0
case "$default" in
    ""|auto_null) broken=1 ;;
esac

# Also check we have at least one non-null sink
if [ "$broken" = "0" ]; then
    has_real=0
    for s in $sinks; do
        case "$s" in
            auto_null) ;;
            *) has_real=1 ;;
        esac
    done
    [ "$has_real" = "0" ] && broken=1
fi

[ "$broken" = "0" ] && exit 0

echo "$(date): audio broken (default=$default, sinks=$sinks), resetting WirePlumber state" >&2

mv ~/.local/state/wireplumber ~/.local/state/wireplumber.bak.$(date +%s) 2>/dev/null
systemctl --user restart wireplumber pipewire pipewire-pulse
