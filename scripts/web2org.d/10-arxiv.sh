#!/usr/bin/env bash
# arXiv handler: fetches the paper PDF + metadata (title, authors, abstract)
# from the arXiv API and saves an org file to WEB_CAPTURE_PAPERS_DIR.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
. "$HERE/lib.sh"

# Pull the arXiv id (with optional vN suffix) from any arxiv URL form.
arxiv_id() {
    printf '%s' "$1" | grep -oP 'arxiv\.org/(?:abs|pdf)/\K[0-9.]+(?:v[0-9]+)?' | head -1
}

case "${1:-}" in
match)
    case "$2" in
        *arxiv.org/abs/*|*arxiv.org/pdf/*) exit 0 ;;
    esac
    exit 1
    ;;
capture)
    url="$2"
    id="$(arxiv_id "$url")"
    [[ -z "$id" ]] && { notify -u critical "Couldn't parse arXiv id from $url"; exit 1; }
    base_id="${id%v*}"

    mkdir -p "$WEB_CAPTURE_PAPERS_DIR"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    notify "Fetching arXiv $id"

    meta="$tmpdir/meta.xml"
    curl -fsSL "https://export.arxiv.org/api/query?id_list=$base_id" -o "$meta"

    title=""; authors=""; summary=""
    if command -v xmllint >/dev/null 2>&1; then
        title="$(xmllint --xpath 'string(//*[local-name()="entry"]/*[local-name()="title"])' "$meta" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
        authors="$(xmllint --xpath '//*[local-name()="entry"]/*[local-name()="author"]/*[local-name()="name"]/text()' "$meta" 2>/dev/null | paste -sd', ' -)"
        summary="$(xmllint --xpath 'string(//*[local-name()="entry"]/*[local-name()="summary"])' "$meta" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
    fi
    [[ -z "$title" ]] && title="arXiv:$id"

    slug="arxiv-${base_id}-$(slugify "$title")"
    out="$WEB_CAPTURE_PAPERS_DIR/${slug}.org"

    pdf="$tmpdir/paper.pdf"
    curl -fsSL "https://arxiv.org/pdf/$id" -o "$pdf"
    txt="$tmpdir/paper.txt"
    pdftotext -layout "$pdf" "$txt" 2>/dev/null || true

    {
        printf '#+TITLE: %s\n' "$title"
        [[ -n "$authors" ]] && printf '#+AUTHORS: %s\n' "$authors"
        printf '#+SOURCE: https://arxiv.org/abs/%s\n' "$id"
        printf '#+ARXIV_ID: %s\n' "$id"
        printf '#+DATE: %s\n\n' "$(date -I)"
        if [[ -n "$summary" ]]; then
            printf '* Abstract\n%s\n\n' "$summary"
        fi
        if [[ -s "$txt" ]]; then
            printf '* Full text\n#+begin_example\n'
            cat "$txt"
            printf '\n#+end_example\n'
        fi
    } > "$out"

    finalize "$out"
    ;;
*)
    echo "Usage: $0 {match|capture} URL" >&2; exit 2 ;;
esac
