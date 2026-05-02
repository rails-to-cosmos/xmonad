#!/bin/sh
# Runtime power tweaks. Detects vendor and applies appropriate knobs.
# Run via xmonad startup or manually. Some require root - those are gated.

set -e

VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
echo "=== Power Tweaks ($VENDOR $PRODUCT) ==="

is_battery() {
    grep -q "Discharging" /sys/class/power_supply/BAT*/status 2>/dev/null
}

# 1. PCIe ASPM (huge effect, no downside on most workloads)
if [ -w /sys/module/pcie_aspm/parameters/policy ]; then
    echo "powersupersave" > /sys/module/pcie_aspm/parameters/policy 2>/dev/null \
        && echo "✓ PCIe ASPM: powersupersave"
fi

# 2. CPU energy preference (intel_pstate / amd-pstate)
if is_battery; then
    epp="power"
else
    epp="balance_performance"
fi
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -w "$f" ] && echo "$epp" > "$f" 2>/dev/null
done
echo "✓ CPU energy_performance_preference: $epp"

# 3. USB autosuspend (saves 1-3W)
for f in /sys/bus/usb/devices/*/power/control; do
    [ -w "$f" ] && echo "auto" > "$f" 2>/dev/null
done
echo "✓ USB autosuspend: auto"

# 4. SATA link power management
for f in /sys/class/scsi_host/host*/link_power_management_policy; do
    [ -w "$f" ] && echo "med_power_with_dipm" > "$f" 2>/dev/null
done

# 5. NVMe APST (built-in; only kernel-side runtime PM tunable)
for f in /sys/class/nvme/nvme*/power/control; do
    [ -w "$f" ] && echo "auto" > "$f" 2>/dev/null
done

# 6. WiFi power save
for iface in $(ls /sys/class/net | grep -E '^wl'); do
    iw dev "$iface" set power_save on 2>/dev/null \
        && echo "✓ WiFi power save: on ($iface)"
done

# 7. Intel HDA audio codec power save (10s idle)
if [ -w /sys/module/snd_hda_intel/parameters/power_save ]; then
    echo "10" > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null \
        && echo "✓ Intel HDA power_save: 10s"
fi

# 8. GPU runtime power management (Intel/AMD/Nvidia)
for f in /sys/class/drm/card*/device/power/control; do
    [ -w "$f" ] && echo "auto" > "$f" 2>/dev/null
done
echo "✓ GPU runtime PM: auto"

# 9. ThinkPad-specific tweaks
if [ "$VENDOR" = "LENOVO" ]; then
    # Battery charge thresholds (preserve battery health: 60-80% range)
    if [ -w /sys/class/power_supply/BAT0/charge_control_start_threshold ] && \
       [ -w /sys/class/power_supply/BAT0/charge_control_end_threshold ]; then
        echo "60" > /sys/class/power_supply/BAT0/charge_control_start_threshold 2>/dev/null
        echo "80" > /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null \
            && echo "✓ Battery charge thresholds: 60-80%"
    fi
fi

# 10. Reduce brightness on battery (only if currently above 70%)
if is_battery; then
    for bl in /sys/class/backlight/*/brightness; do
        max="$(cat "$(dirname "$bl")/max_brightness" 2>/dev/null)"
        cur="$(cat "$bl" 2>/dev/null)"
        [ -z "$max" ] || [ -z "$cur" ] && continue
        if [ "$cur" -gt $((max * 70 / 100)) ]; then
            echo $((max * 50 / 100)) > "$bl" 2>/dev/null \
                && echo "✓ Brightness reduced to 50%"
        fi
    done
fi

echo ""
echo "Current power draw:"
upower -i $(upower -e 2>/dev/null | grep BAT) 2>/dev/null | grep "energy-rate" || true
