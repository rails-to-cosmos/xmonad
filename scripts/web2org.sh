#!/usr/bin/env bash
# Web-capture dispatcher.
#
# Looks at the URL, picks the first matching handler from web2org.d/, and
# delegates the work. The result is an org-mode file in an output directory
# the handler chose (typically a subdir of ~/sync/resources/).
#
# Usage:
#   web2org.sh [URL]
#
# With no URL, opens a rofi prompt pre-filled with the X clipboard.
#
# Handlers
# --------
# Each file matching web2org.d/[0-9][0-9]-*.sh is an executable handler.
# Files run in lexical order, so a smaller numeric prefix = higher priority.
# The handler contract is:
#
#     handler.sh match   URL   # exit 0 to claim this URL, non-zero to pass
#     handler.sh capture URL   # do the work, print the output path on stdout
#
# To add a new content type, drop e.g. 40-mastodon.sh in web2org.d/, source
# config.sh and lib.sh from it, and implement the two subcommands. Done.
#
# Override behavior with environment variables (see web2org.d/config.sh):
#   WEB_CAPTURE_BASE          - root for default output dirs
#   WEB_CAPTURE_ARTICLES_DIR  - HTML articles target
#   WEB_CAPTURE_VIDEOS_DIR    - YouTube target
#   WEB_CAPTURE_PAPERS_DIR    - PDF / arXiv target
#   WEB_CAPTURE_OPEN=1        - spawn an emacsclient frame on success
#   WEB_CAPTURE_COPY_PATH=1   - copy output path to the X clipboard (default on)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# WEB_CAPTURE_TERM=1 : re-exec inside a floating, --hold terminal so all output
# (incl. crash traces) is visible live and stays on screen after exit.
if [[ "${WEB_CAPTURE_TERM:-0}" == 1 && -z "${WEB_CAPTURE_IN_TERM:-}" ]]; then
    exec alacritty --class web2org-term --hold \
        -e env WEB_CAPTURE_IN_TERM=1 "$0" "$@"
fi

# Expose sibling uv-script tools (yt-dlp, jq, xmllint, pdftotext, pdfinfo) to handlers
export PATH="$SCRIPT_DIR:$PATH"
HANDLER_DIR="$SCRIPT_DIR/web2org.d"
. "$HANDLER_DIR/config.sh"
. "$HANDLER_DIR/lib.sh"

# Job-status state for the xmobar `web2org` widget (read by xmobar-status):
#   running/<pid> : one marker per in-flight capture (pid name → liveness check)
#   success       : one line appended per successful capture
#   failed        : one line appended per failed capture
# Under $XDG_RUNTIME_DIR (tmpfs) so counters reset on logout/reboot.
W2O_STATE="${XDG_RUNTIME_DIR:-/tmp}/web2org"
W2O_MARKER="$W2O_STATE/running/$$"
w2o_begin() { mkdir -p "$W2O_STATE/running"; : > "$W2O_MARKER"; }
w2o_ok()    { rm -f "$W2O_MARKER"; printf 'ok\n'   >> "$W2O_STATE/success"; }
w2o_fail()  { rm -f "$W2O_MARKER"; printf 'fail\n' >> "$W2O_STATE/failed"; }
# Safety net: drop the marker even if a handler is killed mid-capture.
trap 'rm -f "$W2O_MARKER" 2>/dev/null' EXIT

# Tee everything to a timestamped log (+ stable "last" symlink) so a quiet
# spawn from xmonad still leaves a full trace to inspect after a failure.
LOG="/tmp/web2org-$(date +%Y%m%d-%H%M%S).log"
ln -sf "$LOG" /tmp/web2org-last.log
exec > >(tee -a "$LOG") 2>&1

# WEB_CAPTURE_DEBUG=1 : add a full shell execution trace to the log.
[[ "${WEB_CAPTURE_DEBUG:-0}" == 1 ]] && set -x

# Pop the log in a floating terminal (only from a GUI, and not if we're already
# running inside the verbose terminal where the trace is already on screen).
# open_trace() {
#     [[ -n "${DISPLAY:-}" && -z "${WEB_CAPTURE_IN_TERM:-}" ]] || return 0
#     alacritty --class web2org-term --hold -e less +G "$LOG" >/dev/null 2>&1 &
# }

url="${1:-}"
if [[ -z "$url" ]]; then
    clip="$(xclip -selection clipboard -o 2>/dev/null || true)"
    url="$(printf '%s' "$clip" | rofi -dmenu -p 'URL' -filter "$clip" || true)"
fi

if [[ -z "${url:-}" ]]; then
    notify -u low "No URL provided"
    exit 1
fi

# Instant feedback the moment the keybind fires.
progress "Working… ($url)"

for h in "$HANDLER_DIR"/[0-9][0-9]-*.sh; do
    [[ -x "$h" ]] || continue
    if "$h" match "$url" 2>/dev/null; then
        w2o_begin
        if ! "$h" capture "$url"; then
            w2o_fail
            notify -u critical "$(basename "$h") failed"
            exit 1
        fi
        w2o_ok
        exit 0
    fi
done

notify -u critical "No handler matched $url"
exit 1
