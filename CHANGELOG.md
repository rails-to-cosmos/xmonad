# Changelog

## 2026-03-11

- Theme dmenu to match xmobar Tokyo Night colors (bg, fg, selection, font)
- Add patched dmenu with line-height support (`-h` flag) to match xmobar height
- Add `install-dmenu.sh` script for building patched dmenu from source
- Remap `M-t` to default (sink floating window), add `M-S-t` for next layout
- Add `M-f` for fullscreen toggle
- Change `Alt+Tab` to dmenu window switcher with app class names in titles
- Add `M-S-Space` for US/RU keyboard layout switching
- Remove keyd dependency, use xkb `ctrl:nocaps` for CapsLock-to-Ctrl remapping
