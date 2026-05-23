#!/usr/bin/env bash
# Generic PDF handler: any URL ending in .pdf or serving application/pdf.
# pdftotext -> wrapped in #+begin_example block.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
. "$HERE/lib.sh"

is_pdf_url() {
    case "$1" in
        *.pdf|*.pdf\?*|*.pdf#*) return 0 ;;
    esac
    [[ "$(content_type "$1")" == application/pdf* ]]
}

case "${1:-}" in
match)
    is_pdf_url "$2"
    ;;
capture)
    url="$2"
    command -v pdftotext >/dev/null 2>&1 || { notify -u critical "pdftotext not installed (poppler)"; exit 1; }

    mkdir -p "$WEB_CAPTURE_PAPERS_DIR"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    notify "Fetching PDF $url"
    pdf="$tmpdir/in.pdf"
    fetch_url "$url" "$pdf"

    title=""
    if command -v pdfinfo >/dev/null 2>&1; then
        title="$(pdfinfo "$pdf" 2>/dev/null | awk -F': +' '/^Title:/{print $2}' | head -1)"
    fi
    if [[ -z "$title" ]]; then
        title="$(basename "${url%%\?*}" .pdf)"
    fi

    slug="$(slugify "$title")"
    [[ -z "$slug" ]] && slug="$(date +%Y%m%d-%H%M%S)"
    out="$WEB_CAPTURE_PAPERS_DIR/${slug}.org"

    txt="$tmpdir/out.txt"
    pdftotext -layout "$pdf" "$txt"

    {
        printf '#+TITLE: %s\n' "$title"
        printf '#+SOURCE: %s\n' "$url"
        printf '#+DATE: %s\n\n' "$(date -I)"
        printf '* Full text\n#+begin_example\n'
        cat "$txt"
        printf '\n#+end_example\n'
    } > "$out"

    finalize "$out"
    ;;
*)
    echo "Usage: $0 {match|capture} URL" >&2; exit 2 ;;
esac
