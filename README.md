# XMonad Desktop Configuration

Minimal XMonad setup with xmobar, targeting Arch Linux on a Framework Laptop 16.

## Installation

```bash
./install.sh
```

This installs all required packages and configures keyd for CapsLock-to-Ctrl remapping.

## Structure

```
~/.config/xmonad/
├── xmonad.hs          # XMonad window manager config
├── build              # GHC build script
├── install.sh         # System package installer
└── README.md

~/.config/xmobar/
└── xmobarrc           # xmobar status bar config
```

## Keybindings

Mod key is **Ctrl+Alt**.

| Key | Action |
|-----|--------|
| Mod+Space | Launch dmenu |
| Mod+Enter | Launch alacritty |
| Mod+b | Toggle xmobar |
| Mod+j/k | Focus next/prev window |
| Mod+Shift+j/k | Swap next/prev window |
| Mod+h/l | Shrink/expand master |
| Mod+Shift+c | Close focused window |
| Mod+Space | Next layout |
| Mod+1-9 | Switch to workspace |
| Mod+Shift+1-9 | Move window to workspace |
| Mod+q | Restart XMonad |
| Mod+Shift+q | Quit XMonad |

## Keyboard Layout

US/RU layout switching via **both Shifts pressed simultaneously**.

CapsLock is remapped to Ctrl via keyd (required for Framework 16 — the QMK firmware sends instant key taps that break xkb-level remapping).

## xmobar Widgets

Brightness, volume, wifi, CPU usage + temperature, memory, disk, battery (with charging/discharging icons), clock, and keyboard layout flags (🇺🇸/🇷🇺).

## Theme

Tokyo Night color scheme:
- Background: `#1a1b26`
- Foreground: `#c0caf5`
- Green: `#9ece6a`
- Yellow: `#e0af68`
- Red: `#f7768e`
- Accent: `#6790eb`
