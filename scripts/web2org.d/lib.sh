# Helpers shared by web-capture handlers. Source this; don't execute.

# notify [-u urgency] MESSAGE...
# Info-level messages share a dunst stack tag so they UPDATE IN PLACE (one
# walking bubble: "Fetching…" -> "Transcribing…" -> "Saved X"). Critical
# errors are NOT tagged, so they pop as separate, persistent bubbles.
notify() {
    local urg="normal"
    local tag=(-h string:x-dunst-stack-tag:web2org)
    if [[ "${1:-}" == "-u" ]]; then
        urg="$2"; shift 2
        [[ "$urg" == "critical" ]] && tag=()
    fi
    notify-send -a web-capture -u "$urg" "${tag[@]}" 'web-capture' "$*" 2>/dev/null || true
}

# progress [-p PERCENT] MESSAGE...
# Like notify (info, in-place) but draws a dunst progress bar when -p is given.
progress() {
    local val=()
    if [[ "${1:-}" == "-p" ]]; then val=(-h "int:value:$2"); shift 2; fi
    notify-send -a web-capture -u normal \
        -h string:x-dunst-stack-tag:web2org "${val[@]}" \
        'web-capture' "$*" 2>/dev/null || true
}

# Lowercase ASCII slug, max 80 chars.
slugify() {
    printf '%s' "$1" \
        | iconv -f utf-8 -t ascii//translit 2>/dev/null \
        | tr -cs 'A-Za-z0-9' '-' \
        | sed 's/^-//; s/-$//' \
        | tr '[:upper:]' '[:lower:]' \
        | cut -c1-80
}

# Extract first <title> from an HTML file. Empty if not found.
html_title() {
    grep -oP '(?<=<title>).*?(?=</title>)' "$1" | head -1 | tr -d '\n' || true
}

# Fetch URL with a real-browser UA. Args: URL output-file
fetch_url() {
    curl -fsSL -A 'Mozilla/5.0' "$1" -o "$2"
}

# HEAD request, lowercased Content-Type. Args: URL
content_type() {
    curl -fsIL -A 'Mozilla/5.0' "$1" 2>/dev/null \
        | awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' \
        | tr -d '\r' | tail -1
}

# Prepend a basic org metadata block to an existing org file.
# Args: file title source [extra header lines...]
prepend_org_meta() {
    local file="$1" title="$2" source="$3"; shift 3
    {
        printf '#+TITLE: %s\n' "$title"
        printf '#+SOURCE: %s\n' "$source"
        printf '#+DATE: %s\n' "$(date -I)"
        local line
        for line in "$@"; do printf '%s\n' "$line"; done
        printf '\n'
        cat "$file"
    } > "$file.tmp" && mv "$file.tmp" "$file"
}

# Convert a WebVTT subtitle file to plain de-duplicated text.
vtt_to_text() {
    awk '
        /^WEBVTT/  { next }
        /^NOTE/    { next }
        /-->/      { next }
        /^[0-9]+$/ { next }
        /^$/       { next }
        {
            gsub(/<[^>]*>/, "")
            sub(/^[[:space:]]+/, "")
            if ($0 != prev && length($0)) { print; prev = $0 }
        }
    ' "$1"
}

# Standard end-of-capture: notify, optionally copy path / open emacs, print path.
# Arg: output file path
finalize() {
    local out="$1"
    notify "Saved $(basename "$out")"
    if [[ "${WEB_CAPTURE_COPY_PATH:-0}" == 1 ]] && command -v xclip >/dev/null 2>&1; then
        printf '%s' "$out" | xclip -selection clipboard 2>/dev/null || true
    fi
    if [[ "${WEB_CAPTURE_OPEN:-0}" == 1 ]] && command -v emacsclient >/dev/null 2>&1; then
        emacsclient -c -n "$out" >/dev/null 2>&1 &
    fi
    printf '%s\n' "$out"
}
