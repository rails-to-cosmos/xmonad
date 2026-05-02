# Framework Laptop 16 — Power Management Guide

**Hardware:** Framework Laptop 16 (AMD Ryzen 9 7940HS + Radeon RX 7600 dGPU)
**OS:** CachyOS, kernel 6.19+
**Date:** 2026-05-02

## Current Baseline Issues

Diagnosed power draw: **~31W idle** (target: 8-15W)
Estimated battery life: **1.4 hours** (target: 6-8h with iGPU)

| Problem                    | Impact        | Status                                             |
|----------------------------|---------------|----------------------------------------------------|
| dGPU (RX 7600) active      | 8-15W         | `power_state: D0`                                  |
| Brightness at 100%         | 3-5W          | Max                                                |
| NVMe power saving disabled | 1-3W          | `nvme_core.default_ps_max_latency_us=0` in cmdline |
| PCIe ASPM not active       | 2-4W          | Default policy (not `powersupersave`)              |
| No power management daemon | 2-5W          | None installed                                     |
| WiFi power save            | 0.5-1W        | Likely off                                         |
| Many wake sources enabled  | Suspend drain | 10+ devices wake in S3/S4                          |

---

## Quick Wins (Apply First)

### 1. Runtime tweaks script

Use the helper at `~/.config/xmonad/scripts/power-tweaks.sh`. Run with sudo for full effect:

```bash
sudo ~/.config/xmonad/scripts/power-tweaks.sh
```

The script applies:
- PCIe ASPM → `powersupersave`
- CPU energy preference → `power`
- USB autosuspend → `auto`
- SATA link power management → `med_power_with_dipm`
- WiFi power save → on
- AMD GPU runtime PM → auto
- Brightness reduction (50%) when on battery and currently >70%

### 2. Lower screen brightness

100% brightness is the single biggest controllable drain. Even 60% saves 3-5W.

Bind in xmonad keybinds:
```haskell
("<XF86MonBrightnessDown>", spawn "brightnessctl -d amdgpu_bl2 set 5%-")
("<XF86MonBrightnessUp>",   spawn "brightnessctl -d amdgpu_bl2 set +5%")
```

---

## Kernel Command Line Changes

Current cmdline has these power-killers:

```
nvme_core.default_ps_max_latency_us=0
```

This **disables NVMe sleep states** (1-3W loss). Originally added to fix freezes; recent kernels handle it better — try removing.

### Recommended cmdline additions

```
pcie_aspm=force
pcie_aspm.policy=powersupersave
amdgpu.runpm=1
```

### Edit instructions (CachyOS / systemd-boot)

```bash
# Find your boot loader entry
ls /boot/loader/entries/

# Edit the active entry, modify the `options` line:
sudo $EDITOR /boot/loader/entries/<your-entry>.conf

# Then rebuild initrd if needed
sudo mkinitcpio -P

# Reboot to apply
```

For GRUB-based systems:
```bash
sudo $EDITOR /etc/default/grub
# Modify GRUB_CMDLINE_LINUX_DEFAULT
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

## dGPU Power Management

The Radeon RX 7600 dGPU should sleep when not in use. Both GPUs being in `D0` state is the biggest single drain.

### Diagnose

```bash
# Who is using the dGPU?
sudo lsof /dev/dri/card1

# Runtime PM status
cat /sys/class/drm/card1/device/power/runtime_usage
cat /sys/class/drm/card1/device/power/runtime_enabled
cat /sys/class/drm/card1/device/power/control
```

### Force iGPU usage for specific apps

```bash
# Use iGPU (saves power)
DRI_PRIME=0 firefox

# Use dGPU (only when needed, e.g., gaming)
DRI_PRIME=1 steam
```

### List render providers

```bash
xrandr --listproviders
```

If something is keeping the dGPU awake (window manager compositor, browser, Discord, etc.), force it onto the iGPU via the `DRI_PRIME=0` environment variable.

---

## Power Management Daemon

Install one (not multiple — they conflict).

### Recommended: `power-profiles-daemon`

Lightweight, AMD-friendly, integrates with desktop:

```bash
sudo pacman -S power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Switch profiles
powerprofilesctl set power-saver
powerprofilesctl set balanced
powerprofilesctl set performance
```

### Alternative: `tuned`

More tunable, official AMD support:

```bash
sudo pacman -S tuned
sudo systemctl enable --now tuned
sudo tuned-adm profile powersave
```

### Alternative: `TLP`

Classic battery saver. **Do not run alongside PPD or tuned.**

```bash
sudo pacman -S tlp
sudo systemctl enable --now tlp
```

---

## Suspend Wake-up Sources

Many devices wake the system from S3/S4, draining battery while the lid is closed.

```bash
# View current wake-up sources
cat /proc/acpi/wakeup

# Disable a wake-up source (toggles state)
sudo sh -c 'echo "GPP0" > /proc/acpi/wakeup'
```

Devices to disable (toggle off):
- `GPP0`, `GPP1`, `GPP6`, `GPP8`, `GP11`, `GP12` — PCIe ports
- `SWUS`, `SWDS` — PCIe switches
- `XHC0`, `XHC1` — USB controllers (keep one if you need USB wake)

Persist across reboots via systemd unit or udev rule.

---

## PowerTOP (Diagnostics)

```bash
sudo pacman -S powertop

# One-time calibration (~10 min, plug in beforehand)
sudo powertop --calibrate

# Interactive view of top consumers + tunables
sudo powertop

# Apply all suggested tweaks
sudo powertop --auto-tune
```

PowerTOP's `--auto-tune` is generally safer than TLP and applies industry-standard kernel tunables.

---

## Verification

After applying changes, re-measure:

```bash
# Wait 10 minutes after unplugging, then check
upower -i $(upower -e | grep BAT) | grep -E "energy-rate|time to empty"
```

Target metrics for Framework 16 AMD:
- Idle (terminal, no GPU acceleration): **8-12W**
- Light browsing: **12-15W**
- Video playback (1080p): **10-15W**

If still seeing >20W idle, the dGPU is the culprit. Check section above.

---

## References

- [Framework Laptop 16 ArchWiki](https://wiki.archlinux.org/title/Framework_Laptop_16)
- [Framework Knowledge Base](https://knowledgebase.frame.work/)
- [amd_pstate driver docs](https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html)
- [PowerTOP documentation](https://01.org/powertop)
