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

# Transliterate Russian Cyrillic to ASCII Latin. glibc's iconv //translit
# turns Cyrillic into '?', so without this Rutube's Russian titles/channels
# would slugify to empty and collapse into videos/unknown-channel/yt-<id>.
# Literal byte substitutions, so it works regardless of locale.
translit_cyrillic() {
    sed -e 's/щ/shch/g; s/Щ/shch/g' \
        -e 's/ё/yo/g;   s/Ё/yo/g'   \
        -e 's/ж/zh/g;   s/Ж/zh/g'   \
        -e 's/ч/ch/g;   s/Ч/ch/g'   \
        -e 's/ш/sh/g;   s/Ш/sh/g'   \
        -e 's/ю/yu/g;   s/Ю/yu/g'   \
        -e 's/я/ya/g;   s/Я/ya/g'   \
        -e 's/х/kh/g;   s/Х/kh/g'   \
        -e 's/ц/ts/g;   s/Ц/ts/g'   \
        -e 's/а/a/g;    s/А/a/g'     \
        -e 's/б/b/g;    s/Б/b/g'     \
        -e 's/в/v/g;    s/В/v/g'     \
        -e 's/г/g/g;    s/Г/g/g'     \
        -e 's/д/d/g;    s/Д/d/g'     \
        -e 's/е/e/g;    s/Е/e/g'     \
        -e 's/з/z/g;    s/З/z/g'     \
        -e 's/и/i/g;    s/И/i/g'     \
        -e 's/й/y/g;    s/Й/y/g'     \
        -e 's/к/k/g;    s/К/k/g'     \
        -e 's/л/l/g;    s/Л/l/g'     \
        -e 's/м/m/g;    s/М/m/g'     \
        -e 's/н/n/g;    s/Н/n/g'     \
        -e 's/о/o/g;    s/О/o/g'     \
        -e 's/п/p/g;    s/П/p/g'     \
        -e 's/р/r/g;    s/Р/r/g'     \
        -e 's/с/s/g;    s/С/s/g'     \
        -e 's/т/t/g;    s/Т/t/g'     \
        -e 's/у/u/g;    s/У/u/g'     \
        -e 's/ф/f/g;    s/Ф/f/g'     \
        -e 's/ы/y/g;    s/Ы/y/g'     \
        -e 's/э/e/g;    s/Э/e/g'     \
        -e 's/ъ//g;     s/Ъ//g'      \
        -e 's/ь//g;     s/Ь//g'
}

# Lowercase ASCII slug, max 80 chars.
slugify() {
    printf '%s' "$1" \
        | translit_cyrillic \
        | iconv -f utf-8 -t ascii//translit 2>/dev/null \
        | tr -cs 'A-Za-z0-9' '-' \
        | tr '[:upper:]' '[:lower:]' \
        | cut -c1-80 \
        | sed 's/^-*//; s/-*$//'
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
