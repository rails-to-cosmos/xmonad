# Web-capture configuration. Override any value via environment variables.

WEB_CAPTURE_BASE="${WEB_CAPTURE_BASE:-$HOME/sync/resources}"

WEB_CAPTURE_ARTICLES_DIR="${WEB_CAPTURE_ARTICLES_DIR:-$WEB_CAPTURE_BASE/articles}"
WEB_CAPTURE_VIDEOS_DIR="${WEB_CAPTURE_VIDEOS_DIR:-$WEB_CAPTURE_BASE/videos}"
WEB_CAPTURE_PAPERS_DIR="${WEB_CAPTURE_PAPERS_DIR:-$WEB_CAPTURE_BASE/papers}"

# 1 = spawn an emacsclient frame on success.
WEB_CAPTURE_OPEN="${WEB_CAPTURE_OPEN:-0}"

# 1 = copy the output path onto the X clipboard on success.
WEB_CAPTURE_COPY_PATH="${WEB_CAPTURE_COPY_PATH:-1}"
