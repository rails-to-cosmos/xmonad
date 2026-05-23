#!/usr/bin/env bash
# YouTube handler: title/description/metadata via yt-dlp, transcript via
# auto-subs when available, falling back to whisper if installed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
. "$HERE/lib.sh"

case "${1:-}" in
match)
    case "$2" in
        *youtube.com/watch*|*youtu.be/*|*youtube.com/shorts/*|*music.youtube.com/*) exit 0 ;;
    esac
    exit 1
    ;;
capture)
    url="$2"
    command -v yt-dlp >/dev/null 2>&1 || { notify -u critical "yt-dlp not installed"; exit 1; }
    command -v jq      >/dev/null 2>&1 || { notify -u critical "jq not installed"; exit 1; }

    mkdir -p "$WEB_CAPTURE_VIDEOS_DIR"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    notify "Fetching YouTube metadata"

    meta="$tmpdir/meta.json"
    yt-dlp --skip-download --dump-json --no-warnings "$url" > "$meta" 2>/dev/null \
        || { notify -u critical "yt-dlp failed for $url"; exit 1; }

    title="$(jq -r '.title // empty' "$meta")"
    channel="$(jq -r '.channel // .uploader // empty' "$meta")"
    upload_date="$(jq -r '.upload_date // empty' "$meta")"
    duration="$(jq -r '.duration_string // empty' "$meta")"
    description="$(jq -r '.description // empty' "$meta")"
    video_id="$(jq -r '.id // empty' "$meta")"

    slug="$(slugify "$title")"
    [[ -z "$slug" ]] && slug="yt-$video_id"
    out="$WEB_CAPTURE_VIDEOS_DIR/${slug}.org"

    notify "Trying auto-subs"
    subs_text=""
    subs_source="none"
    yt-dlp --skip-download \
           --write-auto-subs --write-subs \
           --sub-langs 'en.*,en' --sub-format vtt \
           -o "$tmpdir/%(id)s" "$url" >/dev/null 2>&1 || true

    sub_vtt="$(find "$tmpdir" -maxdepth 1 -name '*.vtt' | head -1)"
    if [[ -n "$sub_vtt" && -s "$sub_vtt" ]]; then
        subs_text="$(vtt_to_text "$sub_vtt")"
        subs_source="youtube-auto"
    elif command -v whisper >/dev/null 2>&1; then
        notify "No subs found, running whisper (slow)"
        audio_base="$tmpdir/audio"
        if yt-dlp -x --audio-format m4a -o "${audio_base}.%(ext)s" "$url" >/dev/null 2>&1; then
            audio_file="$(find "$tmpdir" -maxdepth 1 -name 'audio.*' | head -1)"
            if [[ -n "$audio_file" ]]; then
                whisper "$audio_file" --model "${WHISPER_MODEL:-small}" \
                        --output_format txt --output_dir "$tmpdir" >/dev/null 2>&1 || true
                wtxt="$(find "$tmpdir" -maxdepth 1 -name 'audio*.txt' | head -1)"
                if [[ -n "$wtxt" && -s "$wtxt" ]]; then
                    subs_text="$(cat "$wtxt")"
                    subs_source="whisper"
                fi
            fi
        fi
    fi

    {
        printf '#+TITLE: %s\n' "$title"
        [[ -n "$channel"      ]] && printf '#+CHANNEL: %s\n' "$channel"
        printf '#+SOURCE: %s\n' "$url"
        [[ -n "$upload_date"  ]] && printf '#+UPLOAD_DATE: %s\n' "$upload_date"
        [[ -n "$duration"     ]] && printf '#+DURATION: %s\n' "$duration"
        printf '#+DATE: %s\n' "$(date -I)"
        printf '#+TRANSCRIPT_SOURCE: %s\n\n' "$subs_source"
        if [[ -n "$description" ]]; then
            printf '* Description\n#+begin_quote\n%s\n#+end_quote\n\n' "$description"
        fi
        printf '* Transcript\n'
        if [[ -n "$subs_text" ]]; then
            printf '%s\n' "$subs_text"
        else
            printf '(No transcript available: no auto-subs and whisper not installed.)\n'
        fi
    } > "$out"

    finalize "$out"
    ;;
*)
    echo "Usage: $0 {match|capture} URL" >&2; exit 2 ;;
esac
