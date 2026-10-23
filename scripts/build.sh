#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP="$ROOT/build/macmon.app"
DMG_DIR="$ROOT/build/dmg"
DMG_NAME="macmon.dmg"
BG_TEMP="/tmp/macmon-dmg-background.png"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/MacmonApp" "$APP/Contents/MacOS/macmon"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "error: $ROOT/Resources/AppIcon.icns not found. Run: ./scripts/icons.sh select <name>" >&2
    exit 1
fi
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

# Create DMG with proper layout
if [[ "${CREATE_DMG:-0}" == "1" ]]; then
    echo "Creating DMG..."
    rm -rf "$DMG_DIR"
    mkdir -p "$DMG_DIR"
    
    # Copy app to DMG staging
    cp -R "$APP" "$DMG_DIR/"
    
    # Create Applications symlink
    ln -sf /Applications "$DMG_DIR/Applications"
    
    # Copy background image to temp location (needed for AppleScript)
    cp "$ROOT/Resources/dmg-background.png" "$BG_TEMP"
    cp "$ROOT/Resources/dmg-background.png" "$DMG_DIR/.background.png"
    
    # Create DMG (read-write first for layout)
    hdiutil create -volname "macmon" -srcfolder "$DMG_DIR" -ov -format UDRW "$DMG_NAME"
    
    # Mount DMG to apply layout
    echo "Mounting DMG to apply layout..."
    ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_NAME")
    MOUNT_DIR=$(echo "$ATTACH_OUTPUT" | tail -1 | awk '{print $NF}')
    
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        # Apply background and layout using AppleScript
        osascript <<EOF
        tell application "Finder"
            tell disk "macmon"
                open
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {400, 100, 1040, 500}
                set viewOptions to the icon view options of container window
                set arrangement of viewOptions to not arranged
                set icon size of viewOptions to 128
                set background picture of viewOptions to (POSIX file "$BG_TEMP" as alias)
                set position of item "macmon.app" of container window to {160, 200}
                set position of item "Applications" of container window to {480, 200}
                close
                open
                delay 1
            end tell
        end tell
EOF
        
        # Sync and unmount
        sync
        hdiutil detach "$MOUNT_DIR" -force
        
        # Convert to compressed UDZO
        hdiutil convert "$DMG_NAME" -format UDZO -o "${DMG_NAME%.dmg}-compressed.dmg" -ov
        mv "${DMG_NAME%.dmg}-compressed.dmg" "$DMG_NAME"
        
        # Cleanup
        rm -f "$BG_TEMP"
        
        echo "Created $DMG_NAME"
    else
        echo "Failed to mount DMG"
        echo "Attach output: $ATTACH_OUTPUT"
        rm -f "$BG_TEMP"
        exit 1
    fi
fi