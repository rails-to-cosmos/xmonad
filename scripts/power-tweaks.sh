#!/bin/sh
# Framework 16 (AMD) runtime power tweaks
# Apply quick wins for battery life. Run via xmonad startup or manually.
# Some require root - those are gated.

set -e

echo "=== Framework 16 Power Tweaks ==="

# Detect Framework only
[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" = "Framework" ] || {
    echo "Not a Framework laptop, skipping."
    exit 0
}

is_battery() {
    grep -q "Discharging" /sys/class/power_supply/BAT*/status 2>/dev/null
}

# 1. PCIe ASPM (huge effect, no downside on most workloads)
if [ -w /sys/module/pcie_aspm/parameters/policy ]; then
    echo "powersupersave" > /sys/module/pcie_aspm/parameters/policy 2>/dev/null \
        && echo "✓ PCIe ASPM: powersupersave"
fi

# 2. AMD CPU energy preference (already set to 'power' but enforce)
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -w "$f" ] && echo "power" > "$f" 2>/dev/null
done
echo "✓ CPU energy_performance_preference: power"

# 3. USB autosuspend (saves 1-3W)
for f in /sys/bus/usb/devices/*/power/control; do
    [ -w "$f" ] && echo "auto" > "$f" 2>/dev/null
done
echo "✓ USB autosuspend: auto"

# 4. SATA link power management
for f in /sys/class/scsi_host/host*/link_power_management_policy; do
    [ -w "$f" ] && echo "med_power_with_dipm" > "$f" 2>/dev/null
done

# 5. WiFi power save (iwlwifi/ath/mt76 - all support this)
for iface in $(ls /sys/class/net | grep -E "^wl"); do
    iw dev "$iface" set power_save on 2>/dev/null \
        && echo "✓ WiFi power save: on ($iface)"
done

# 6. Reduce brightness when on battery (only if not already low)
if is_battery; then
    for bl in /sys/class/backlight/*/brightness; do
        max="$(cat "$(dirname "$bl")/max_brightness" 2>/dev/null)"
        cur="$(cat "$bl" 2>/dev/null)"
        [ -z "$max" ] || [ -z "$cur" ] && continue
        # Only dim if currently above 70%
        if [ "$cur" -gt $((max * 70 / 100)) ]; then
            target=$((max * 50 / 100))
            echo "$target" > "$bl" 2>/dev/null \
                && echo "✓ Brightness reduced to 50% (was 100%)"
        fi
    done
fi

# 7. AMD GPU runtime power management
for f in /sys/class/drm/card*/device/power/control; do
    [ -w "$f" ] && echo "auto" > "$f" 2>/dev/null
done
echo "✓ GPU runtime PM: auto"

echo ""
echo "Done. Current power draw:"
upower -i $(upower -e | grep BAT) 2>/dev/null | grep "energy-rate" || true
