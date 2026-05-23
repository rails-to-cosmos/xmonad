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
# Expose sibling uv-script tools (yt-dlp, jq, xmllint, pdftotext, pdfinfo) to handlers
export PATH="$SCRIPT_DIR:$PATH"
HANDLER_DIR="$SCRIPT_DIR/web2org.d"
. "$HANDLER_DIR/config.sh"
. "$HANDLER_DIR/lib.sh"

url="${1:-}"
if [[ -z "$url" ]]; then
    clip="$(xclip -selection clipboard -o 2>/dev/null || true)"
    url="$(printf '%s' "$clip" | rofi -dmenu -p 'URL' -filter "$clip" || true)"
fi

if [[ -z "${url:-}" ]]; then
    notify -u low "No URL provided"
    exit 1
fi

for h in "$HANDLER_DIR"/[0-9][0-9]-*.sh; do
    [[ -x "$h" ]] || continue
    if "$h" match "$url" 2>/dev/null; then
        if ! "$h" capture "$url"; then
            notify -u critical "Handler $(basename "$h") failed for $url"
            exit 1
        fi
        exit 0
    fi
done

notify -u critical "No handler matched $url"
exit 1
