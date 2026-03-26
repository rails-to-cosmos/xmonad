# XMonad Desktop Configuration

Minimal XMonad setup with xmobar, portable across multiple laptops.

## Installation

```bash
make install
```

This detects the current OS and runs the appropriate install script (`arch-install.sh` or `mint-install.sh`), then builds patched dmenu.

`scripts/install-dmenu.sh` clones dmenu from suckless, applies the line-height patch (for `-h` flag support), and installs it. This allows dmenu height to match xmobar.

## Structure

```
~/.config/xmonad/
├── xmonad.hs              # XMonad window manager config
├── scripts/
│   ├── build.sh               # GHC build script (xmonad + xmobar-status)
│   ├── xmobar-status.hs       # Compiled Haskell binary for 8 xmobar widgets
│   ├── theme-sync.sh          # Syncs xmobar theme with Emacs danneskjold theme
│   ├── redshift-status.sh     # Redshift day/night indicator
│   ├── install.sh             # OS-detecting install dispatcher
│   ├── arch-install.sh        # Arch Linux package installer
│   ├── mint-install.sh        # Linux Mint/Ubuntu package installer
│   ├── install-dmenu.sh       # Builds dmenu with line-height patch
│   ├── setup-inputs.sh        # Keyboard repeat rate & natural scrolling
│   └── setup-keyd.sh          # CapsLock→Ctrl via keyd
├── dmenu/
│   └── dmenu-lineheight-5.2.diff
└── README.md

~/.config/xmobar/
└── xmobarrc              # xmobar status bar config
```

## xmobar-status.hs

A single compiled Haskell binary that powers most xmobar widgets. Auto-compiled by `build.sh` when xmonad recompiles (mod+q).

Subcommands: `battery`, `brightness`, `cputemp`, `volume`, `wifi`, `vpn`, `emacs`, `gpu`

All widgets:
- Auto-detect hardware (battery name, backlight device, hwmon path, GPU)
- Cache discovered paths in `/tmp/` for efficiency
- Load theme colors from `/tmp/xmobar-theme` (synced from Emacs)

## Keybindings

Mod key is **Ctrl+Alt**.

| Key | Action |
|-----|--------|
| Ctrl+q | Close focused window |
| Mod+Enter | Launch emacsclient |
| Mod+Space | Launch rofi |
| Mod+Shift+Space | Launch rofi (discrete GPU mode) |
| Mod+b | Toggle xmobar |
| Mod+f | Toggle fullscreen |
| Mod+t | Next layout |
| Ctrl+Alt+Left/Right | Switch workspace |
| Ctrl+Alt+Shift+Left/Right | Move window to workspace and follow |
| Mod+Shift+t | Scratchpad terminal |
| Mod+s | Scratchpad btop |
| Mod+v | Scratchpad pavucontrol |
| Mod+e | Scratchpad emacs |
| Mod+c | Telegram |
| Mod+Shift+c | Slack |
| Mod+Escape | Power menu (lock/logout/suspend/reboot/shutdown) |
| Mod+j/k | Focus next/prev window |
| Mod+Shift+j/k | Swap next/prev window |
| Mod+h/l | Shrink/expand master |
| Mod+1-9 | Switch to workspace |
| Mod+Shift+1-9 | Move window to workspace |

## Keyboard Layout

US/RU layout switching via **both Shifts pressed together**.

CapsLock is remapped to Ctrl via xkb (`ctrl:nocaps` option in `setxkbmap`).

## Theme

[danneskjold-theme](https://github.com/rails-to-cosmos/danneskjold-theme) color scheme, auto-synced from Emacs (dark/light variants).

| Role | Dark | Light |
|------|------|-------|
| Background | `#000000` | `#FFFFFF` |
| Foreground | `#FFFFFF` | `#000000` |
| Good/success | `#B6E63E` | `#B6E63E` |
| Warning | `#FFCC00` | `#FFCC00` |
| Error | `#E74C3C` | `#E74C3C` |
| Accent | `#4CB5F5` | `#4CB5F5` |
| Dim | `#525254` | `#C0C5CF` |
| Border | `#21252B` | `#C0C5CF` |

`theme-sync.sh` polls Emacs every 30s. When the active danneskjold variant changes, it updates `/tmp/xmobar-theme` (read by all widgets) and restarts xmobar with matching bg/fg/border colors.

## Hardware Auto-detection

All hardware-specific paths are discovered at runtime, not hardcoded:

- **Battery**: first `BAT*` in `/sys/class/power_supply/`
- **CPU temp**: `coretemp` or `k10temp` hwmon
- **Backlight**: first device in `/sys/class/backlight/`
- **GPU**: discrete GPUs with `gpu_busy_percent` (hidden when none exist)
- **Volume**: PipeWire via `wpctl`
- **WiFi**: `wlan0` interface via `iw`
- **VPN**: WireGuard interfaces via `ip link`
