# XMonad Desktop Configuration

Minimal XMonad setup with xmobar on a Framework Laptop 16.

## Installation

```bash
make install
```

This detects the current OS and runs the appropriate install script (`arch-install.sh` or `mint-install.sh`), then builds patched dmenu.

`scripts/install-dmenu.sh` clones dmenu from suckless, applies the line-height patch (for `-h` flag support), and installs it. This allows dmenu height to match xmobar.

## Structure

```
~/.config/xmonad/
├── xmonad.hs          # XMonad window manager config
├── build              # GHC build script
├── scripts/
│   ├── install.sh         # OS-detecting install dispatcher
│   ├── arch-install.sh    # Arch Linux package installer
│   ├── mint-install.sh    # Linux Mint/Ubuntu package installer
│   ├── install-dmenu.sh   # Builds dmenu with line-height patch
│   ├── setup-inputs.sh    # Keyboard repeat rate & natural scrolling
│   ├── setup-keyd.sh      # CapsLock→Ctrl via keyd
│   ├── gpu-status.sh      # GPU status for xmobar
│   ├── redshift-status.sh # Redshift status for xmobar
│   └── wifi-status.sh     # WiFi status for xmobar
├── dmenu/             # dmenu patches
│   └── dmenu-lineheight-5.2.diff
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
| Mod+t | Sink floating window into tiled layout |
| Mod+Shift+t | Next layout |
| Mod+f | Toggle fullscreen |
| Mod+j/k | Focus next/prev window |
| Mod+Shift+j/k | Swap next/prev window |
| Mod+h/l | Shrink/expand master |
| Mod+Shift+c | Close focused window |
| Mod+1-9 | Switch to workspace |
| Mod+Shift+1-9 | Move window to workspace |
| Mod+Shift+Space | Toggle keyboard layout (US/RU) |
| Alt+Tab | Focus next window |
| Mod+q | Restart XMonad |
| Mod+Shift+q | Quit XMonad |

## Keyboard Layout

US/RU layout switching via **Mod+Shift+Space**.

CapsLock is remapped to Ctrl via xkb (`ctrl:nocaps` option in `setxkbmap`).

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
