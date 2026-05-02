#!/bin/sh
# Framework 16 dGPU control - manage Radeon RX 7600 power state
# Usage:
#   dgpu-control.sh           - rofi interactive menu
#   dgpu-control.sh --status  - print current state
#   dgpu-control.sh --auto    - kernel-managed power (recommended)
#   dgpu-control.sh --on      - force dGPU always on (for gaming)
#   dgpu-control.sh --remove  - remove from PCI bus (max savings)
#   dgpu-control.sh --rescan  - bring removed dGPU back

set -e

# 1. Locate the dGPU automatically (non-primary VGA controller)
DGPU_PCI=""
for f in /sys/bus/pci/devices/*/boot_vga; do
    if [ "$(cat "$f" 2>/dev/null)" = "0" ]; then
        DGPU_PCI=$(basename "$(dirname "$f")")
        break
    fi
done

DGPU_DIR=""
DGPU_NAME=""
if [ -n "$DGPU_PCI" ]; then
    DGPU_DIR="/sys/bus/pci/devices/$DGPU_PCI"
    DGPU_NAME=$(lspci -s "${DGPU_PCI#0000:}" 2>/dev/null | sed 's/.*: //' | cut -c1-60)
fi

# 2. Notification helper (uses notify-send when in graphical context)
notify() {
    if [ -n "${DISPLAY:-}" ] && command -v notify-send >/dev/null 2>&1; then
        notify-send -i video-display "dGPU Control" "$1"
    fi
    echo "$1"
}

# 3. Privileged execution helper - uses pkexec from GUI, sudo from terminal
priv_run() {
    # If launched from a terminal, sudo can prompt; otherwise pkexec
    if [ -t 0 ] || [ -t 1 ]; then
        sudo "$@"
    elif command -v pkexec >/dev/null 2>&1; then
        pkexec "$@"
    else
        notify "✗ Need pkexec or terminal sudo to run privileged ops"
        return 1
    fi
}

# 3. Status reporting
show_status() {
    if [ -z "$DGPU_PCI" ]; then
        echo "No discrete GPU detected"
        return 1
    fi
    echo "dGPU:           $DGPU_NAME"
    echo "PCI:            $DGPU_PCI"
    if [ -e "$DGPU_DIR" ]; then
        echo "Power state:    $(cat "$DGPU_DIR/power_state" 2>/dev/null)"
        echo "Runtime status: $(cat "$DGPU_DIR/power/runtime_status" 2>/dev/null)"
        echo "Runtime ctrl:   $(cat "$DGPU_DIR/power/control" 2>/dev/null)"
        users=$(cat "$DGPU_DIR/power/runtime_usage" 2>/dev/null || echo "?")
        echo "Active users:   $users"
    else
        echo "Bus state:      REMOVED (not present on PCI bus)"
    fi
}

# 4. Operations (require sudo)
set_runtime_pm() {
    mode="$1"
    if [ -z "$DGPU_DIR" ] || [ ! -e "$DGPU_DIR" ]; then
        notify "✗ dGPU not present (run --rescan first?)"
        return 1
    fi
    priv_run sh -c "echo '$mode' > '$DGPU_DIR/power/control'"
    case "$mode" in
        auto) notify "✓ dGPU: auto (kernel-managed power, sleeps when idle)" ;;
        on)   notify "✓ dGPU: forced ON (gaming mode, full performance)" ;;
    esac
}

remove_dgpu() {
    if [ -z "$DGPU_DIR" ] || [ ! -e "$DGPU_DIR" ]; then
        notify "dGPU already removed"
        return 0
    fi
    # Warn if displays connected via dGPU
    if [ -n "${DISPLAY:-}" ]; then
        connected=$(find /sys/class/drm -name "card*-DP-*" -path "*$DGPU_PCI*" \
            -exec sh -c 'cat "$1/status" 2>/dev/null | grep -q connected && echo "$1"' _ {} \; 2>/dev/null | wc -l)
        if [ "$connected" -gt 0 ]; then
            notify "⚠ $connected display(s) connected via dGPU - removal will disconnect them!"
        fi
    fi
    priv_run sh -c "echo 1 > '$DGPU_DIR/remove'"
    notify "✓ dGPU removed from PCI bus (max power savings)"
}

rescan_pci() {
    priv_run sh -c "echo 1 > /sys/bus/pci/rescan"
    notify "✓ PCI bus rescanned (dGPU should be back)"
    sleep 1
    [ -e "$DGPU_DIR" ] && set_runtime_pm "auto" || true
}

# 5. Interactive rofi menu
show_menu() {
    if ! command -v rofi >/dev/null 2>&1; then
        echo "rofi not installed; use --auto, --on, --remove, --rescan, or --status"
        exit 1
    fi

    state="not detected"
    if [ -n "$DGPU_PCI" ]; then
        if [ -e "$DGPU_DIR" ]; then
            rs=$(cat "$DGPU_DIR/power/runtime_status" 2>/dev/null)
            ctrl=$(cat "$DGPU_DIR/power/control" 2>/dev/null)
            state="$rs / $ctrl"
        else
            state="REMOVED"
        fi
    fi

    choice=$(printf '%s\n' \
        "Auto (recommended) — kernel manages, sleeps when idle" \
        "Force ON — keep awake (gaming, GPU compute)" \
        "Remove — disconnect from PCI bus (max power saving)" \
        "Rescan — bring removed dGPU back" \
        "Status — show details" \
        | rofi -dmenu -i -p "dGPU [$state]")

    case "$choice" in
        Auto*)    set_runtime_pm "auto" ;;
        Force*)   set_runtime_pm "on" ;;
        Remove*)  remove_dgpu ;;
        Rescan*)  rescan_pci ;;
        Status*)  show_status | rofi -dmenu -p "dGPU Status" -theme-str 'window {width: 600px;}' ;;
        '')       exit 0 ;;
    esac
}

# 6. Argument dispatch
case "${1:-}" in
    --status|-s) show_status ;;
    --on)        set_runtime_pm "on" ;;
    --auto|--off) set_runtime_pm "auto" ;;
    --remove)    remove_dgpu ;;
    --rescan)    rescan_pci ;;
    --help|-h)
        sed -n '2,9p' "$0" | sed 's/^# *//'
        ;;
    "")          show_menu ;;
    *)           echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
esac
