#!/bin/sh

set -eu

SCRIPT_NAME="magnetile"
MODE="normal"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--normal|--restart]

Build, install, enable, and reload Magnetile in a KDE Wayland session.

Options:
  --normal    Package/install with make, then reconfigure and start KWin scripting.
  --restart   Package/install with make, then restart KWin completely.
  -h, --help  Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --normal)
            MODE="normal"
            ;;
        --restart|--full|--kwin-restart)
            MODE="restart"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "$(basename "$0"): Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
    echo "$(basename "$0"): Magnetile supports Wayland sessions only." >&2
    exit 1
fi

for command in make kwriteconfig6 qdbus6; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "$(basename "$0"): Missing required command: ${command}" >&2
        exit 1
    fi
done

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${REPO_DIR}"

echo "Magnetile clean reload (${MODE})"
echo "Repository: ${REPO_DIR}"
echo
echo "1. Packaging and installing with make..."
make

echo
echo "2. Enabling ${SCRIPT_NAME} in kwinrc..."
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_NAME}Enabled" true

if [ "${MODE}" = "restart" ]; then
    echo
    echo "3. Restarting KWin. Use this after shortcut declarations or signal handlers change."
    qdbus6 org.kde.KWin /KWin org.kde.KWin.replace
    echo
    echo "KWin restart requested."
else
    echo
    echo "3. Reconfiguring KWin and starting scripting..."
    qdbus6 org.kde.KWin /KWin reconfigure
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
    echo
    echo "Normal reload requested."
fi

echo
echo "Next steps:"
echo "  - Watch recent logs:"
echo "      journalctl --user -u plasma-kwin_wayland --since \"1 minute ago\""
echo "  - Confirm shortcut actions:"
echo "      qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.shortcutNames | rg \"Magnetile\""
echo "  - If shortcuts or signal callbacks still look stale, rerun:"
echo "      tools/reload-clean.sh --restart"
