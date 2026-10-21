#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP="$ROOT/build/macmon.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/MacmonApp" "$APP/Contents/MacOS/macmon"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/macmon"

IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"macmon-dev"'; then
    IDENTITY="macmon-dev"
fi

codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1
echo "built $APP (signed: $IDENTITY)"
if [[ "$IDENTITY" == "-" ]]; then
    echo "note: ad-hoc signature. Create a self-signed 'macmon-dev' identity to keep the Keychain grant across rebuilds."
fi
