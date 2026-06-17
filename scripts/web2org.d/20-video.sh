#!/usr/bin/env bash
# Video handler (yt-dlp): title/description/metadata via yt-dlp, transcript
# via auto-subs when available, falling back to whisper if installed.
# Matches YouTube and Rutube video URLs — drop more yt-dlp-supported site
# patterns into the match list below to extend it. Downloads the video
# itself next to the org file:
#   $WEB_CAPTURE_VIDEOS_DIR/{channel-slug}/{video-slug}.org
#   $WEB_CAPTURE_VIDEOS_DIR/{channel-slug}/{video-slug}.mp4
#
# Playlists: a YouTube *playlist page* (`…/playlist?list=…`, or a `watch?…`
# URL carrying `list=` but NO `v=`) is enumerated and every not-yet-downloaded
# entry is captured. A `watch?v=…&list=…` link is treated as a single video
# (you navigated to a specific one), so only that video is captured. Whether an
# entry is "already downloaded" is derived purely from the files on disk (video
# ids found in existing org files) — no separate ledger to drift out of sync.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"
. "$HERE/lib.sh"

# Most-recent per-video tmpdir; the EXIT trap is a safety net (capture_one also
# removes its tmpdir explicitly before returning, so at most one can leak).
tmpdir=""
pljson=""
w2o_queue=""   # playlist queue-depth marker for the xmobar web2org widget
trap 'rm -rf "${tmpdir:-}" 2>/dev/null; rm -f "${pljson:-}" "${w2o_queue:-}" 2>/dev/null' EXIT

# --- playlist detection -----------------------------------------------------
# Echo the playlist id and succeed IFF the URL is a *playlist page*: a YouTube
# URL with a real `list=` id and NO specific video selected (`v=`). youtu.be /
# /shorts/ / /embed/ links always denote a single video, so they never match.
# Autoplay Mixes/Radio (RD…/UL…) are excluded — they are effectively infinite.
playlist_id_of() {
    local u="$1" id
    case "$u" in
        *youtube.com/playlist[?]*|*music.youtube.com/playlist[?]*) : ;;
        *youtube.com/watch[?]*|*music.youtube.com/watch[?]*)
            case "$u" in *[?\&]v=[A-Za-z0-9_-]*) return 1 ;; esac ;;
        *) return 1 ;;
    esac
    id="$(printf '%s' "$u" | sed -n 's/.*[?&]list=\([^&#]*\).*/\1/p')"
    [ -n "$id" ] || return 1
    case "$id" in RD*|UL*) return 1 ;; esac
    printf '%s' "$id"
}

# Every YouTube video id already captured anywhere under the videos dir,
# derived from the files themselves (so deleting a file un-downloads it):
#   #+VIDEO_ID: <id>   lines (written by capture_one), and
#   ids embedded in #+SOURCE: youtube URLs (back-compat with files written
#   before VIDEO_ID existed). One id per line, sorted/unique.
downloaded_ids() {
    local dir="$WEB_CAPTURE_VIDEOS_DIR"
    [ -d "$dir" ] || return 0
    {
        grep -rhoE '^#\+VIDEO_ID:[[:space:]]*[A-Za-z0-9_-]+' "$dir" 2>/dev/null \
            | sed -E 's/^#\+VIDEO_ID:[[:space:]]*//'
        grep -rhE '^#\+SOURCE:.*(youtube\.com|youtu\.be)' "$dir" 2>/dev/null \
            | grep -oE '([?&]v=|youtu\.be/|/shorts/)[A-Za-z0-9_-]+' \
            | sed -E 's#([?&]v=|youtu\.be/|/shorts/)##'
    } 2>/dev/null | sort -u || true
}

# --- single-video capture ---------------------------------------------------
# capture_one URL — fetch one video (metadata + mp4 + transcript) and write its
# org file. On success sets CAPTURED_PATH to the org path and returns 0; on a
# hard failure (metadata fetch) returns non-zero. A failed video/subtitle
# download is non-fatal (the org file is still written). Set CO_QUIET=1 to
# suppress the step-by-step progress notifications (the playlist loop drives its
# own [i/n] progress instead). Critical error notifications always show.
CAPTURED_PATH=""
co_progress() { [ "${CO_QUIET:-0}" = 1 ] && return 0; progress "$@"; }
# Like co_progress, for one-off notifications: silenced inside a playlist loop
# (failures are coalesced into one summary bubble) but shown for single videos.
co_notify() { [ "${CO_QUIET:-0}" = 1 ] && return 0; notify "$@"; }

capture_one() {
    local url="$1"
    tmpdir="$(mktemp -d)"

    co_progress -p 10 "Video — fetching metadata"

    local meta="$tmpdir/meta.json"
    if ! yt-dlp --skip-download --dump-json --no-warnings --socket-timeout 30 "$url" > "$meta" 2>/dev/null; then
        co_notify -u critical "yt-dlp failed for $url"
        rm -rf "$tmpdir"; tmpdir=""
        return 1
    fi

    local title channel upload_date duration description video_id
    title="$(jq -r '.title // empty' "$meta")"
    channel="$(jq -r '.channel // .uploader // empty' "$meta")"
    upload_date="$(jq -r '.upload_date // empty' "$meta")"
    duration="$(jq -r '.duration_string // empty' "$meta")"
    description="$(jq -r '.description // empty' "$meta")"
    video_id="$(jq -r '.id // empty' "$meta")"

    local slug channel_slug
    slug="$(slugify "$title")"
    [[ -z "$slug" ]] && slug="yt-$video_id"
    channel_slug="$(slugify "$channel")"
    [[ -z "$channel_slug" ]] && channel_slug="unknown-channel"

    local outdir out video_file
    outdir="$WEB_CAPTURE_VIDEOS_DIR/$channel_slug"
    mkdir -p "$outdir" || { co_notify -u critical "mkdir failed: $outdir"; rm -rf "$tmpdir"; tmpdir=""; return 1; }
    out="$outdir/${slug}.org"
    video_file="$outdir/${slug}.mp4"

    co_progress -p 25 "Downloading video"
    if ! yt-dlp -f 'bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b' \
                --merge-output-format mp4 --no-warnings --socket-timeout 30 \
                -o "$video_file" "$url" >/dev/null 2>&1; then
        co_notify -u critical "video download failed for $url (continuing with org only)"
        video_file=""
    fi

    co_progress -p 55 "Trying auto-subs"
    local subs_text="" subs_source="none" sub_vtt
    yt-dlp --skip-download --socket-timeout 30 \
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
        local audio_src="$video_file"
        if [[ -z "$audio_src" || ! -s "$audio_src" ]]; then
            co_progress -p 60 "No subs — downloading audio"
            yt-dlp -x --audio-format m4a --socket-timeout 30 -o "$tmpdir/audio.%(ext)s" "$url" >/dev/null 2>&1 || true
            audio_src="$(find "$tmpdir" -maxdepth 1 -name 'audio.*' | head -1)"
        fi
        if [[ -n "$audio_src" && -s "$audio_src" ]]; then
            co_progress -p 70 "Transcribing with whisper (${WHISPER_MODEL:-small}, slow)…"
            whisper "$audio_src" --model "${WHISPER_MODEL:-small}" \
                    --output_format txt --output_dir "$tmpdir" >/dev/null 2>&1 || true
            local wtxt
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
        # Stable dedup key for playlist re-syncs (see downloaded_ids).
        [[ -n "$video_id"     ]] && printf '#+VIDEO_ID: %s\n' "$video_id"
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
    } > "$out" || { co_notify -u critical "write failed: $out"; rm -rf "$tmpdir"; tmpdir=""; return 1; }

    co_progress -p 95 "Writing org file"
    CAPTURED_PATH="$out"
    rm -rf "$tmpdir"; tmpdir=""
    return 0
}

# --- playlist capture -------------------------------------------------------
# Pop a GUI confirmation before bulk-downloading a large playlist. Returns 0 to
# proceed, non-zero to cancel. Honors WEB_CAPTURE_PLAYLIST_YES=1 (skip prompt)
# and, when there is no GUI/rofi to ask with, proceeds (with a warning) rather
# than silently stalling a deliberately headless invocation.
confirm_large_playlist() {
    local title="$1" n="$2" choice
    if [ -n "${DISPLAY:-}" ] && command -v rofi >/dev/null 2>&1; then
        choice="$(printf 'Download all %d\nCancel\n' "$n" \
            | rofi -dmenu -i -p "Playlist '$title': $n new — download?" 2>/dev/null || true)"
        case "$choice" in
            "Download all "*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    notify -u critical "Playlist '$title': $n new videos, no GUI to confirm — proceeding"
    return 0
}

# capture_playlist URL PLAYLIST_ID — enumerate the playlist and capture every
# entry not already on disk. Per-video failures are non-fatal; returns non-zero
# only if there was work to do and nothing succeeded.
capture_playlist() {
    local url="$1" plid="$2"

    co_progress -p 5 "Playlist — enumerating"
    # Not 'local': the EXIT trap cleans this global on abort/signal during the
    # (potentially slow) enumeration. Reset to "" after each explicit rm.
    pljson="$(mktemp)"
    if ! yt-dlp --flat-playlist --dump-single-json --no-warnings --socket-timeout 30 "$url" > "$pljson" 2>/dev/null; then
        notify -u critical "yt-dlp failed to read playlist $url"
        rm -f "$pljson"; pljson=""; return 1
    fi
    local pl_title; pl_title="$(jq -r '.title // empty' "$pljson")"
    [ -n "$pl_title" ] || pl_title="$plid"

    # Already-downloaded ids (filesystem-derived).
    local -A have=()
    local id
    while IFS= read -r id; do [ -n "$id" ] && have["$id"]=1; done < <(downloaded_ids)

    # Live playlist entries. Unavailable (private/deleted/region-blocked) entries
    # keep a valid id but report a null duration (and null title), so filter on
    # duration to drop them — otherwise they're classified "new" on every re-sync
    # and fail capture forever (their per-video metadata fetch errors out). This
    # also drops currently-live/upcoming streams (duration null), which we can't
    # archive anyway and which would otherwise stall the serial loop indefinitely.
    local -a ids=() titles=()
    local ttl
    while IFS=$'\t' read -r id ttl; do
        [ -n "$id" ] || continue
        ids+=("$id"); titles+=("$ttl")
    done < <(jq -r '.entries[]? | select(type=="object" and .id != null and .duration != null) | [.id, (.title // "")] | @tsv' "$pljson")
    rm -f "$pljson"; pljson=""

    local total=${#ids[@]}
    if [ "$total" -eq 0 ]; then
        notify -u critical "Playlist '$pl_title' has no playable videos"
        return 1
    fi

    # Which entries are new?
    local -a new_ids=() new_titles=()
    local i
    for ((i = 0; i < total; i++)); do
        [ -n "${have[${ids[i]}]:-}" ] && continue
        new_ids+=("${ids[i]}"); new_titles+=("${titles[i]}")
    done
    local n=${#new_ids[@]}

    if [ "$n" -eq 0 ]; then
        progress -p 100 "Playlist '$pl_title' — already complete ($total videos)"
        notify "Nothing new in '$pl_title' ($total videos)"
        return 0
    fi
    notify "Playlist '$pl_title': $total videos, $n new"

    # Confirm before a large bulk download.
    local thresh="${WEB_CAPTURE_PLAYLIST_CONFIRM_THRESHOLD:-20}"
    if [ "$n" -gt "$thresh" ] && [ "${WEB_CAPTURE_PLAYLIST_YES:-0}" != 1 ]; then
        if ! confirm_large_playlist "$pl_title" "$n"; then
            notify "Cancelled: '$pl_title' ($n new videos)"
            return 0
        fi
    fi

    # Publish the queue depth so the xmobar web2org widget shows how many videos
    # are still enqueued behind the one in-progress job (otherwise a whole
    # playlist reads as a single "1 in progress"). Keyed by our pid in the same
    # state dir the dispatcher/daemon use; the widget sweeps it if we're
    # SIGKILLed, and the EXIT trap removes it on normal exit.
    w2o_queue="${W2O_STATE:-${XDG_RUNTIME_DIR:-/tmp}/web2org}/queue/$$"
    mkdir -p "$(dirname "$w2o_queue")" 2>/dev/null || true
    printf '%s\n' "$n" > "$w2o_queue" 2>/dev/null || true

    # Capture each new video. CO_QUIET silences capture_one's own progress/notify
    # so the [i/n] counter below stays the live message and per-video failures
    # don't each spawn a persistent critical bubble — they're coalesced below.
    local ok=0 fail=0 idx pct vid vtitle
    local -a failed_titles=()
    for ((i = 0; i < n; i++)); do
        idx=$((i + 1))
        vid="${new_ids[i]}"; vtitle="${new_titles[i]}"
        pct=$(( 5 + (idx * 90) / n ))
        # Videos still waiting after the one we're about to start (so spinner=1
        # active + queue=this sums to the real remaining count).
        printf '%s\n' "$((n - idx))" > "$w2o_queue" 2>/dev/null || true
        progress -p "$pct" "[$idx/$n] ${vtitle:0:60}"
        if CO_QUIET=1 capture_one "https://www.youtube.com/watch?v=$vid"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1)); failed_titles+=("${vtitle:-$vid}")
        fi
    done
    rm -f "$w2o_queue"; w2o_queue=""

    progress -p 100 "Playlist '$pl_title' — done"
    notify "Playlist '$pl_title': $ok downloaded, $fail failed, $((total - n)) already had"
    # One coalesced critical for the failures: lib.sh notify() drops the dunst
    # stack-tag for criticals, so one-per-video would pile up as N persistent
    # bubbles. Length-capped to keep the bubble sane.
    if [ "$fail" -gt 0 ]; then
        local list="${failed_titles[*]}"
        notify -u critical "Playlist '$pl_title': $fail failed — ${list:0:200}"
    fi
    [ "$ok" -eq 0 ] && [ "$fail" -gt 0 ] && return 1
    return 0
}

# --- entry point ------------------------------------------------------------
case "${1:-}" in
match)
    case "$2" in
        *youtube.com/watch*|*youtu.be/*|*youtube.com/shorts/*|*youtube.com/playlist*|*music.youtube.com/*) exit 0 ;;
        *rutube.ru/video/*|*rutube.ru/play/embed/*|*rutube.ru/shorts/*) exit 0 ;;
    esac
    exit 1
    ;;
capture)
    url="$2"
    command -v yt-dlp >/dev/null 2>&1 || { notify -u critical "yt-dlp not installed"; exit 1; }
    command -v jq      >/dev/null 2>&1 || { notify -u critical "jq not installed"; exit 1; }

    if plid="$(playlist_id_of "$url")"; then
        capture_playlist "$url" "$plid"
    else
        if ! capture_one "$url"; then exit 1; fi
        finalize "$CAPTURED_PATH"
    fi
    ;;
*)
    echo "Usage: $0 {match|capture} URL" >&2; exit 2 ;;
esac
