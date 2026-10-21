#!/bin/zsh
set -euo pipefail

case "${1:-}" in
    "") ;;
    -h|--help)
        echo "usage: ./scripts/install.sh"
        echo "Builds, installs or updates ~/Applications/macmon.app, and loads the launch agent."
        exit 0
        ;;
    *)
        echo "unknown argument: $1" >&2
        echo "usage: ./scripts/install.sh" >&2
        exit 2
        ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"

DEST="$HOME/Applications/macmon.app"
PLIST="$HOME/Library/LaunchAgents/dev.arkab.macmon.plist"
UID_NUM="$(id -u)"

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"

launchctl bootout "gui/$UID_NUM" "$PLIST" >/dev/null 2>&1 || true
pkill -f "$HOME/Applications/macmon.app/Contents/MacOS/macmon" >/dev/null 2>&1 || true

rm -rf "$DEST"
cp -R "$ROOT/build/macmon.app" "$DEST"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.arkab.macmon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/Applications/macmon.app/Contents/MacOS/macmon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>dev.arkab.macmon</string>
    </array>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/dev.arkab.macmon"

sleep 1
echo "installed $DEST"
echo "launch agent: $PLIST"
pgrep -fl "macmon.app/Contents/MacOS/macmon" || echo "warning: process not running yet"
