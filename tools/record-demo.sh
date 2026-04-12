#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEDIA_DIR="$ROOT_DIR/media"
FPS=15
MAX_WIDTH=800

usage() {
    cat <<'USAGE'
Usage:
  bash tools/record-demo.sh MODE

Modes:
  selector
  dragdrop
  edgesnapping
  layouts
  shortcuts
  connected-resize
  theming

Outputs are written to media/ as MODE.gif, except theming writes theming.png.
Use slurp to select the capture region when prompted.
USAGE
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Missing dependency: %s\n' "$1" >&2
        printf 'Install on CachyOS/Arch with: yay -S --noconfirm wf-recorder slurp ffmpeg\n' >&2
        exit 1
    fi
}

record_gif() {
    local mode="$1"
    local raw="$MEDIA_DIR/${mode}.mp4"
    local palette="$MEDIA_DIR/${mode}-palette.png"
    local gif="$MEDIA_DIR/${mode}.gif"
    local region
    local recorder_pid

    require_cmd slurp
    require_cmd wf-recorder
    require_cmd ffmpeg

    mkdir -p "$MEDIA_DIR"

    printf 'Select the region for %s with slurp.\n' "$mode"
    region="$(slurp)"

    printf 'Recording %s. Press Enter here when the demo is complete.\n' "$raw"
    rm -f "$raw" "$palette" "$gif"
    wf-recorder -g "$region" -f "$raw" &
    recorder_pid="$!"
    read -r
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true

    printf 'Optimizing %s...\n' "$gif"
    ffmpeg -y -i "$raw" \
        -vf "fps=${FPS},scale='min(${MAX_WIDTH},iw)':-1:flags=lanczos,palettegen=stats_mode=diff" \
        "$palette"
    ffmpeg -y -i "$raw" -i "$palette" \
        -lavfi "fps=${FPS},scale='min(${MAX_WIDTH},iw)':-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -loop 0 "$gif"
    rm -f "$palette" "$raw"
    printf 'Wrote %s\n' "$gif"
}

capture_theming() {
    local raw="$MEDIA_DIR/theming.mp4"
    local png="$MEDIA_DIR/theming.png"
    local region
    local recorder_pid

    require_cmd slurp
    require_cmd wf-recorder
    require_cmd ffmpeg

    mkdir -p "$MEDIA_DIR"

    printf 'Select the static theming screenshot region with slurp.\n'
    region="$(slurp)"
    printf 'Recording a short theming clip. Press Enter here once the overlay is visible.\n'
    rm -f "$raw" "$png"
    wf-recorder -g "$region" -f "$raw" &
    recorder_pid="$!"
    read -r
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true
    ffmpeg -y -sseof -0.1 -i "$raw" -frames:v 1 "$png"
    rm -f "$raw"
    printf 'Wrote %s\n' "$png"
}

mode="${1:-}"

case "$mode" in
    selector|dragdrop|edgesnapping|layouts|shortcuts|connected-resize)
        record_gif "$mode"
        ;;
    theming)
        capture_theming
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        printf 'Unknown mode: %s\n\n' "$mode" >&2
        usage >&2
        exit 2
        ;;
esac
