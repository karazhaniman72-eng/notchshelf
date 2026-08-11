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

# The copy the installer falls back to, committed so that the one-line install
# works before anybody has drafted a release.
mkdir -p download
cp "$ZIP" download/NotchShelf.zip

echo
echo "Packed:  $(pwd)/$ZIP"
echo "Shipped: $(pwd)/download/NotchShelf.zip  (commit this)"
echo "sha256:  $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Next: commit download/NotchShelf.zip, or draft a release tagged v$VERSION"
echo "and drop the dist zip on it — a release takes precedence when there is one."
