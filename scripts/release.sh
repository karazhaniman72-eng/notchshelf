#!/bin/bash
# Packs a built NotchShelf.app into a zip that can be handed to someone else.
#
# The everyday build signs with the self-made "NotchShelf" certificate so that
# privacy grants survive a rebuild. That certificate lives in one keychain and
# nowhere else, so on anybody else's Mac it is an unknown authority. The copy
# that leaves this machine is re-signed ad-hoc instead: no identity to fail to
# recognise, and the app still launches once the quarantine flag is off.
set -e
cd "$(dirname "$0")/.."

APP="NotchShelf.app"
DIST="dist"

./build.sh release

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$DIST/NotchShelf-$VERSION.zip"

rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP" "$DIST/$APP"
codesign --force --deep --sign - "$DIST/$APP"

# ditto, not zip: a plain zip loses the symlinks and permissions a bundle needs.
ditto -c -k --keepParent "$DIST/$APP" "$ZIP"
rm -rf "$DIST/$APP"

echo
echo "Packed: $(pwd)/$ZIP"
echo "sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Next: draft a release tagged v$VERSION on GitHub and drop that zip on it."
