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
    local raw="$MEDIA_DIR/.${mode}.recording.mp4"
    local palette="$MEDIA_DIR/.${mode}.palette.png"
    local tmp_gif="$MEDIA_DIR/.${mode}.gif"
    local gif="$MEDIA_DIR/${mode}.gif"
    local log="$MEDIA_DIR/.${mode}.wf-recorder.log"
    local region
    local recorder_pid

    require_cmd slurp
    require_cmd wf-recorder
    require_cmd ffmpeg

    mkdir -p "$MEDIA_DIR"

    printf 'Select the region for %s with slurp.\n' "$mode"
    region="$(slurp)"

    printf 'Recording %s. Press Enter here when the demo is complete.\n' "$raw"
    rm -f "$raw" "$palette" "$tmp_gif" "$log"
    wf-recorder -g "$region" -f "$raw" 2>"$log" &
    recorder_pid="$!"
    sleep 0.5
    if ! kill -0 "$recorder_pid" 2>/dev/null; then
        printf 'wf-recorder failed to start.\n' >&2
        cat "$log" >&2
        exit 1
    fi
    read -r
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true

    if [ ! -s "$raw" ]; then
        printf 'wf-recorder did not create %s.\n' "$raw" >&2
        printf 'Recorder log:\n' >&2
        cat "$log" >&2
        exit 1
    fi

    printf 'Optimizing %s...\n' "$gif"
    ffmpeg -y -i "$raw" \
        -vf "fps=${FPS},scale='min(${MAX_WIDTH},iw)':-1:flags=lanczos,palettegen=stats_mode=diff" \
        "$palette"
    ffmpeg -y -i "$raw" -i "$palette" \
        -lavfi "fps=${FPS},scale='min(${MAX_WIDTH},iw)':-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -loop 0 "$tmp_gif"
    mv "$tmp_gif" "$gif"
    rm -f "$palette" "$raw" "$log"
    printf 'Wrote %s\n' "$gif"
}

capture_theming() {
    local raw="$MEDIA_DIR/.theming.recording.mp4"
    local tmp_png="$MEDIA_DIR/.theming.png"
    local png="$MEDIA_DIR/theming.png"
    local log="$MEDIA_DIR/.theming.wf-recorder.log"
    local region
    local recorder_pid

    require_cmd slurp
    require_cmd wf-recorder
    require_cmd ffmpeg

    mkdir -p "$MEDIA_DIR"

    printf 'Select the static theming screenshot region with slurp.\n'
    region="$(slurp)"
    printf 'Recording a short theming clip. Press Enter here once the overlay is visible.\n'
    rm -f "$raw" "$tmp_png" "$log"
    wf-recorder -g "$region" -f "$raw" 2>"$log" &
    recorder_pid="$!"
    sleep 0.5
    if ! kill -0 "$recorder_pid" 2>/dev/null; then
        printf 'wf-recorder failed to start.\n' >&2
        cat "$log" >&2
        exit 1
    fi
    read -r
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true

    if [ ! -s "$raw" ]; then
        printf 'wf-recorder did not create %s.\n' "$raw" >&2
        printf 'Recorder log:\n' >&2
        cat "$log" >&2
        exit 1
    fi

    ffmpeg -y -sseof -0.1 -i "$raw" -frames:v 1 "$tmp_png"
    mv "$tmp_png" "$png"
    rm -f "$raw" "$log"
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
