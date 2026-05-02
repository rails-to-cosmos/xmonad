# Caps Lock → Ctrl on Framework Laptop 16

**Hardware:** Framework Laptop 16 (USB keyboard module 32ac:0012)
**OS:** CachyOS, kernel 6.19+
**Last updated:** 2026-05-02

## The Problem

Framework 16 keyboard sends **kernel-level autorepeat events** for Caps Lock when held — confirmed via `sudo showkey`:

```
keycode 58 press
keycode 58 press     ← autorepeat
keycode 58 press     ← autorepeat (40+ times for a held key)
keycode 58 release
```

This breaks any **X11-level** Caps→Ctrl remap (`setxkbmap ctrl:nocaps`, xmodmap, etc.) because:

- Each kernel autorepeat becomes a separate Ctrl press event in X11
- Modifier state gets confused (rapid press/release cycles)
- Combos like `C-s` print just `s`; `C-Up` happens to work because arrows are quick presses

## Why setxkbmap / xset Don't Fix It

| Approach                    | Why it fails                                              |
|-----------------------------|-----------------------------------------------------------|
| `setxkbmap ctrl:nocaps`     | Maps Caps to Ctrl at X11 — autorepeats still happen       |
| `xset -r 66`                | Disables X11 internal autorepeat, but kernel still sends repeats |
| `xmodmap`                   | Same X11-level limitation                                 |

These all run **above** the kernel's input layer.

## The Fix: keyd

[`keyd`](https://github.com/rvaiya/keyd) is a userspace daemon that:

1. **Grabs the keyboard exclusively** at `/dev/input/event*` (evdev level)
2. **Translates keys** before they reach the kernel input subsystem
3. **Reinjects** translated events via uinput
4. The kernel/X11 see a proper `KEY_LEFTCTRL` press — no autorepeat issue

## Setup

### Install (already in `arch-install.sh`)

```bash
sudo pacman -S keyd
```

### Configuration

`/etc/keyd/default.conf`:

```ini
[ids]

32ac:0012      # Framework 16 ANSI keyboard
32ac:0014      # Framework 16 numpad

[main]

capslock = leftcontrol
```

If keyd doesn't catch the keyboard, use a wildcard match:

```ini
[ids]

*

[main]

capslock = leftcontrol
```

### Enable + start

```bash
sudo systemctl enable --now keyd
```

### Important: remove conflicting X11 remaps

xmonad.hs startup hook should be:

```haskell
spawn "setxkbmap -layout us,ru -option '' -option grp:shifts_toggle"
```

**No** `ctrl:nocaps`, **no** `xset -r 66` — keyd handles it kernel-side.

## Verification

### 1. keyd is grabbing the keyboard

```bash
sudo journalctl -u keyd --no-pager | grep "DEVICE: match"
```

Should show entries for `32ac:0012` (keyboard) and `32ac:0014` (numpad).

### 2. Modifier mapping is clean (no Caps in modifier list)

```bash
xmodmap | head -10
```

Expected:
```
control     Control_L (0x25), Control_R (0x69)
lock        Caps_Lock (0x42)
```

The Caps keycode 0x42 is back to Caps_Lock at X11 — but **physical keypresses don't reach X11 as Caps**, they're already Ctrl from keyd.

### 3. In Emacs

- `Caps + s` → isearch
- `Caps + c, Caps + x, Caps + v` → all work
- `Caps + arrows` → still work
- **Hold Caps for 5 seconds** → no spurious presses, no Caps Lock toggle

## Troubleshooting

### keyd doesn't catch the keyboard

Check device match:

```bash
sudo journalctl -u keyd --no-pager | tail -30
```

If only the numpad shows (`32ac:0014` but not `0012`), use wildcard `*` in `[ids]` section.

### Caps still acts as Caps Lock

`keyd` might not be running:

```bash
systemctl status keyd
sudo systemctl restart keyd
```

After restart, replug or rescan input devices:

```bash
sudo udevadm trigger --subsystem-match=input
```

### Logout / restart fixes nothing

The keyboard might have multiple sub-interfaces. Check:

```bash
ls /dev/input/by-id/ | grep -i framework
```

Each `event-*` is a separate interface. keyd needs to grab the one carrying actual key events (usually `event-kbd` or the lowest-numbered one).

## Why Not udev hwdb?

We tried `KEYBOARD_KEY_70039=leftctrl` in `/etc/udev/hwdb.d/10-framework-keyboard.hwdb`. The compiled hwdb didn't include the rule (verified via `strings /etc/udev/hwdb.bin`). The Framework 16 keyboard's modalias might use AT-style scancodes rather than HID, requiring a different rule format. keyd avoids this by working with evdev keycodes directly.

## References

- [keyd GitHub](https://github.com/rvaiya/keyd)
- [Framework Laptop 16 ArchWiki - Keyboard section](https://wiki.archlinux.org/title/Framework_Laptop_16)
- Linux input layer docs: `/sys/kernel/debug/input/`
