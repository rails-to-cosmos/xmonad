#!/usr/bin/env bash
# Catch-all HTML handler. Always matches; should remain last (highest numeric prefix).
# Uses readability-cli (if present) to pre-clean, then pandoc html -> org.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
. "$HERE/lib.sh"

case "${1:-}" in
match)
    exit 0
    ;;
capture)
    url="$2"
    command -v pandoc >/dev/null 2>&1 || { notify -u critical "pandoc not installed"; exit 1; }

    mkdir -p "$WEB_CAPTURE_ARTICLES_DIR"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    notify "Fetching $url"
    html="$tmpdir/in.html"
    fetch_url "$url" "$html"

    if command -v readable >/dev/null 2>&1; then
        cleaned="$tmpdir/clean.html"
        if readable "$html" > "$cleaned" 2>/dev/null && [[ -s "$cleaned" ]]; then
            html="$cleaned"
        fi
    fi

    title="$(html_title "$html")"
    [[ -z "$title" ]] && title="$(date +%Y%m%d-%H%M%S)-untitled"

    slug="$(slugify "$title")"
    [[ -z "$slug" ]] && slug="$(date +%Y%m%d-%H%M%S)"
    out="$WEB_CAPTURE_ARTICLES_DIR/${slug}.org"

    pandoc -f html -t org \
        --wrap=none \
        --mathjax \
        --shift-heading-level-by=1 \
        "$html" -o "$out"

    prepend_org_meta "$out" "$title" "$url"

    finalize "$out"
    ;;
*)
    echo "Usage: $0 {match|capture} URL" >&2; exit 2 ;;
esac
