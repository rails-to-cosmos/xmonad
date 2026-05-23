#!/usr/bin/env bash
# Convert a webpage to an org-mode file (with LaTeX math preserved) using pandoc.
#
# Usage:
#   web2org.sh [URL]
#
# If URL is omitted, opens a rofi prompt pre-filled with the X clipboard.
# Output dir is $WEB2ORG_DIR (default: ~/sync/resources/articles).
# Opens the resulting .org in your running emacs daemon.

set -euo pipefail

OUT_DIR="${WEB2ORG_DIR:-$HOME/sync/resources/articles}"
mkdir -p "$OUT_DIR"

url="${1:-}"
if [[ -z "$url" ]]; then
    clip="$(xclip -selection clipboard -o 2>/dev/null || true)"
    url="$(printf '%s' "$clip" | rofi -dmenu -p 'URL' -filter "$clip" || true)"
fi

if [[ -z "${url:-}" ]]; then
    notify-send 'web2org' 'No URL provided'
    exit 1
fi

notify-send 'web2org' "Fetching $url"

tmphtml="$(mktemp --suffix=.html)"
trap 'rm -f "$tmphtml"' EXIT

# Some sites block default curl UA; pretend to be a normal browser.
curl -fsSL -A 'Mozilla/5.0' "$url" -o "$tmphtml" || {
    notify-send -u critical 'web2org' "curl failed for $url"
    exit 1
}

# If `readable` (readability-cli) is installed, pre-clean the HTML so pandoc
# doesn't drag in nav/sidebar/footer junk.
if command -v readable >/dev/null 2>&1; then
    cleaned="$(mktemp --suffix=.html)"
    trap 'rm -f "$tmphtml" "$cleaned"' EXIT
    if readable "$tmphtml" > "$cleaned" 2>/dev/null && [[ -s "$cleaned" ]]; then
        tmphtml="$cleaned"
    fi
fi

# Pull a title out of the HTML for the filename / org #+TITLE.
title="$(grep -oP '(?<=<title>).*?(?=</title>)' "$tmphtml" | head -1 | tr -d '\n' || true)"
[[ -z "$title" ]] && title="$(date +%Y%m%d-%H%M%S)-untitled"

slug="$(printf '%s' "$title" \
    | iconv -f utf-8 -t ascii//translit 2>/dev/null \
    | tr -cs 'A-Za-z0-9' '-' \
    | sed 's/^-//; s/-$//' \
    | tr '[:upper:]' '[:lower:]' \
    | cut -c1-80)"
[[ -z "$slug" ]] && slug="$(date +%Y%m%d-%H%M%S)"
out="$OUT_DIR/${slug}.org"

# --wrap=none           : keep long lines (better for diffing & editing)
# --mathjax             : preserve math; in org output this becomes $...$ / $$...$$
# --shift-heading-level-by=1 : demote so the page H1 becomes an org level-2 heading,
#                              leaving the #+TITLE as the top-level identity.
pandoc -f html -t org \
    --wrap=none \
    --mathjax \
    --shift-heading-level-by=1 \
    "$tmphtml" -o "$out"

# Prepend org metadata.
{
    printf '#+TITLE: %s\n' "$title"
    printf '#+SOURCE: %s\n' "$url"
    printf '#+DATE: %s\n\n' "$(date -I)"
    cat "$out"
} > "$out.tmp" && mv "$out.tmp" "$out"

notify-send 'web2org' "Saved $(basename "$out")"

# Open in the existing emacs daemon (matches your M-<Return> binding).
# emacsclient -c -n "$out" &
