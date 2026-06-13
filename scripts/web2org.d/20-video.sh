#!/usr/bin/env bash
# Video handler (yt-dlp): title/description/metadata via yt-dlp, transcript
# via auto-subs when available, falling back to whisper if installed.
# Matches YouTube and Rutube video URLs — drop more yt-dlp-supported site
# patterns into the match list below to extend it. Downloads the video
# itself next to the org file:
#   $WEB_CAPTURE_VIDEOS_DIR/{channel-slug}/{video-slug}.org
#   $WEB_CAPTURE_VIDEOS_DIR/{channel-slug}/{video-slug}.mp4
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
. "$HERE/lib.sh"

case "${1:-}" in
match)
    case "$2" in
        *youtube.com/watch*|*youtu.be/*|*youtube.com/shorts/*|*music.youtube.com/*) exit 0 ;;
        *rutube.ru/video/*|*rutube.ru/play/embed/*|*rutube.ru/shorts/*) exit 0 ;;
    esac
    exit 1
    ;;
capture)
    url="$2"
    command -v yt-dlp >/dev/null 2>&1 || { notify -u critical "yt-dlp not installed"; exit 1; }
    command -v jq      >/dev/null 2>&1 || { notify -u critical "jq not installed"; exit 1; }

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    progress -p 10 "Video — fetching metadata"

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
    channel_slug="$(slugify "$channel")"
    [[ -z "$channel_slug" ]] && channel_slug="unknown-channel"

    outdir="$WEB_CAPTURE_VIDEOS_DIR/$channel_slug"
    mkdir -p "$outdir"
    out="$outdir/${slug}.org"
    video_file="$outdir/${slug}.mp4"

    progress -p 25 "Downloading video"
    if ! yt-dlp -f 'bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b' \
                --merge-output-format mp4 --no-warnings \
                -o "$video_file" "$url" >/dev/null 2>&1; then
        notify -u critical "video download failed for $url (continuing with org only)"
        video_file=""
    fi

    progress -p 55 "Trying auto-subs"
    subs_text=""
    subs_source="none"
    yt-dlp --skip-download \
           --write-auto-subs --write-subs \
           --sub-langs 'en.*,en' --sub-format vtt \
           -o "$tmpdir/%(id)s" "$url" >/dev/null 2>&1 || true

    sub_vtt="$(find "$tmpdir" -maxdepth 1 -name '*.vtt' | head -1)"
    if [[ -n "$sub_vtt" && -s "$sub_vtt" ]]; then
        subs_text="$(vtt_to_text "$sub_vtt")"
        subs_source="auto-subs"
    elif command -v whisper >/dev/null 2>&1; then
        # Prefer the already-downloaded video as the transcription source;
        # only fetch an audio-only stream if the video download failed.
        audio_src="$video_file"
        if [[ -z "$audio_src" || ! -s "$audio_src" ]]; then
            progress -p 60 "No subs — downloading audio"
            yt-dlp -x --audio-format m4a -o "$tmpdir/audio.%(ext)s" "$url" >/dev/null 2>&1 || true
            audio_src="$(find "$tmpdir" -maxdepth 1 -name 'audio.*' | head -1)"
        fi
        if [[ -n "$audio_src" && -s "$audio_src" ]]; then
            progress -p 70 "Transcribing with whisper (${WHISPER_MODEL:-small}, slow)…"
            whisper "$audio_src" --model "${WHISPER_MODEL:-small}" \
                    --output_format txt --output_dir "$tmpdir" >/dev/null 2>&1 || true
            wtxt="$(find "$tmpdir" -maxdepth 1 -name '*.txt' | head -1)"
            if [[ -n "$wtxt" && -s "$wtxt" ]]; then
                subs_text="$(cat "$wtxt")"
                subs_source="whisper"
            fi
        fi
    fi

    {
        printf '#+TITLE: %s\n' "$title"
        [[ -n "$channel"      ]] && printf '#+CHANNEL: %s\n' "$channel"
        printf '#+SOURCE: %s\n' "$url"
        [[ -n "$video_file"   ]] && printf '#+VIDEO: [[file:%s.mp4]]\n' "$slug"
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

    progress -p 95 "Writing org file"
    finalize "$out"
    ;;
*)
    echo "Usage: $0 {match|capture} URL" >&2; exit 2 ;;
esac
