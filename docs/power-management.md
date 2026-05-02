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
("<XF86MonBrightnessDown>", spawn "brightnessctl --class=backlight set 5%-")
("<XF86MonBrightnessUp>",   spawn "brightnessctl --class=backlight set +5%")
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

## Further Optimizations

After the initial fixes (achieved ~43% reduction: 31W → 17.7W), these can squeeze out additional savings to reach the 8-15W idle target.

### High Impact (-3 to -5W combined)

#### 1. AC/Battery profile auto-switching

Switch CPU/GPU policies based on power source via `power-profiles-daemon` + udev:

```bash
sudo pacman -S power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon
```

```ini
# /etc/udev/rules.d/99-power-profile.rules
SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/usr/bin/powerprofilesctl set power-saver"
SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/usr/bin/powerprofilesctl set balanced"
```

#### 2. Display refresh rate on battery

Framework 16 panel runs at 165Hz by default — drops 1.5-2W at 60Hz:

```bash
xrandr --output eDP --rate 60     # save battery
xrandr --output eDP --rate 165    # back to perf
```

A keybind/script for interactive selection is wired up at `~/.config/xmonad/scripts/refresh-rate.sh` (M-S-r).

#### 3. AMD iGPU power profile

Lock iGPU clocks to low on battery:

```bash
echo "low" | sudo tee /sys/class/drm/card2/device/power_dpm_force_performance_level   # battery
echo "auto" | sudo tee /sys/class/drm/card2/device/power_dpm_force_performance_level  # AC
```

Saves 1-2W during idle.

### Medium Impact (-1 to -2W combined)

#### 4. Audio codec power save

```bash
# /etc/modprobe.d/audio-power.conf
options snd_hda_intel power_save=1 power_save_controller=Y
```

#### 5. Bluetooth disable on battery

Add to `power-tweaks.sh`:
```bash
is_battery && rfkill block bluetooth
```

#### 6. Idle suspend

```ini
# /etc/systemd/logind.conf.d/suspend.conf
[Login]
HandleLidSwitch=suspend
IdleAction=suspend
IdleActionSec=15min
```

### Low Impact (-0.5 to -1W combined)

#### 7. Disable unused services

Audit and disable services not in use:

```bash
systemctl list-timers
systemctl list-units --type=service --state=running

# Common targets if not needed:
sudo systemctl disable bluetooth.service       # if no BT use
sudo systemctl disable cups.service            # no printing
sudo systemctl disable ModemManager.service    # no cellular
```

#### 8. Unload unused kernel modules

```bash
lsmod | head -30

# Examples:
sudo modprobe -r snd_hda_codec_hdmi  # if no HDMI audio
sudo modprobe -r uvcvideo            # webcam (toggleable via M-S-v)
```

#### 9. Compositor tuning (picom)

If running picom on battery:
- Disable shadows
- Use `xrender` backend instead of `glx`
- Reduce/disable blur

---

## Diagnostic-Driven Workflow

After each change, measure:

```bash
upower -i $(upower -e | grep BAT) | grep energy-rate
```

Or watch the live xmobar power widget (`%power%`) for real-time delta.

---

## Power Reduction Tracker

| Phase                                | Power Draw   | Notes                                    |
|--------------------------------------|--------------|------------------------------------------|
| Initial baseline                     | 31W          | dGPU active, brightness 100%, no tweaks  |
| After power-tweaks.sh + dGPU disable | 17.7W        | -43%; in yellow zone                     |
| Target (idle, terminal)              | 8-12W        | Green zone                               |
| Target (light browsing)              | 12-15W       | Green zone                               |

---

## References

- [Framework Laptop 16 ArchWiki](https://wiki.archlinux.org/title/Framework_Laptop_16)
- [Framework Knowledge Base](https://knowledgebase.frame.work/)
- [amd_pstate driver docs](https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html)
- [PowerTOP documentation](https://01.org/powertop)
