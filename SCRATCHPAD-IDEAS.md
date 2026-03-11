# Scratchpad Ideas

Potential scratchpads to add to the XMonad config.

## Productivity

- **Notes/scratch buffer** — `emacsclient -c -F '((name . "scratchnotes"))' ~/notes.org` for quick capture
- **Calculator** — `alacritty --class scratchcalc -e qalc` or `python3`
- **File manager** — `thunar` or `pcmanfm`

## Development

- **lazygit** — `alacritty --class scratchgit -e lazygit` for quick git operations
- **Documentation browser** — `firefox --class scratchdocs` for API docs

## System

- **Network manager** — `nm-connection-editor` for wifi/VPN settings
- **Bluetooth** — `blueman-manager` for bluetooth device management

## Media

- **Music player** — `spotify` or `alacritty --class scratchmusic -e ncmpcpp`

## Notes

Install missing packages as needed:
```bash
sudo pacman -S thunar qalculate-gtk lazygit nm-connection-editor blueman
```
