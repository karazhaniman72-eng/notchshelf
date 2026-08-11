#!/bin/bash
# Builds NotchShelf.app next to the project.
set -e
cd "$(dirname "$0")"

CONFIG=${1:-release}
swift build -c "$CONFIG"

BIN=".build/$CONFIG/NotchShelf"
APP="NotchShelf.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchShelf"

# Regenerate the icon only when it is missing; drawing it takes a few seconds.
if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>NotchShelf</string>
    <key>CFBundleDisplayName</key>
    <string>NotchShelf</string>
    <key>CFBundleIdentifier</key>
    <string>local.iman.notchshelf</string>
    <key>CFBundleExecutable</key>
    <string>NotchShelf</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>NotchShelf shows today's events in the notch panel.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>NotchShelf shows today's events in the notch panel.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchShelf controls Spotify playback from the notch panel.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity when there is one.
#
# An ad-hoc signature has no identity: macOS keys every privacy grant to the
# hash of the binary, so each rebuild is a brand new app to it, and Calendar,
# Downloads and the screenshots folder all have to be granted again. Signed with
# one self-made certificate, the identity stops changing and the grants stick.
IDENTITY="NotchShelf"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Signed as: $IDENTITY"
else
    codesign --force --deep --sign - "$APP" 2>/dev/null || true
    echo "Signed ad-hoc — permissions will be asked again after every build."
fi
echo "Built: $(pwd)/$APP"
