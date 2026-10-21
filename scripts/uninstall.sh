#!/bin/zsh
set -euo pipefail

case "${1:-}" in
    ""|--purge) ;;
    -h|--help)
        echo "usage: ./scripts/uninstall.sh [--purge]"
        echo "  no flag   remove app and launch agent, keep cached stats"
        echo "  --purge   also remove cached Claude stats and JSONL offsets"
        exit 0
        ;;
    *)
        echo "unknown argument: $1" >&2
        echo "usage: ./scripts/uninstall.sh [--purge]" >&2
        exit 2
        ;;
esac

PLIST="$HOME/Library/LaunchAgents/dev.arkab.macmon.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true
pkill -f "$HOME/Applications/macmon.app/Contents/MacOS/macmon" >/dev/null 2>&1 || true
rm -f "$PLIST"
rm -rf "$HOME/Applications/macmon.app"

if [[ "${1:-}" == "--purge" ]]; then
    rm -f "$HOME/Library/Application Support/macmon/claude.json" \
          "$HOME/Library/Application Support/macmon/jsonl-state.json"
    rmdir "$HOME/Library/Application Support/macmon" 2>/dev/null || true
    echo "removed app, launch agent, and cached state"
else
    echo "removed app and launch agent (cached Claude stats kept; use --purge)"
fi
