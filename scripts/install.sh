#!/bin/bash
# Installs the latest released NotchShelf.app into /Applications.
#
# Meant to be run by somebody who has never opened a terminal for anything else:
#   curl -fsSL https://raw.githubusercontent.com/karazhaniman72-eng/notchshelf/main/scripts/install.sh | bash
#
# It downloads the zip attached to the newest release, unpacks it, strips the
# quarantine flag macOS puts on anything downloaded, and opens the app. Nothing
# else is touched and nothing is left behind.
set -e

REPO="${NOTCHSHELF_REPO:-karazhaniman72-eng/notchshelf}"
APP="/Applications/NotchShelf.app"

echo "Looking for the newest NotchShelf release..."
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"browser_download_url"' | grep '\.zip"' | head -1 \
    | cut -d'"' -f4)

if [ -z "$URL" ]; then
    echo "No release with a zip on it at github.com/$REPO — nothing to install."
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $(basename "$URL")..."
curl -fL --progress-bar "$URL" -o "$TMP/NotchShelf.zip"
ditto -x -k "$TMP/NotchShelf.zip" "$TMP"

if [ ! -d "$TMP/NotchShelf.app" ]; then
    echo "The zip did not contain NotchShelf.app."
    exit 1
fi

# A running copy cannot be replaced underneath itself.
osascript -e 'quit app "NotchShelf"' 2>/dev/null || true
rm -rf "$APP"
mv "$TMP/NotchShelf.app" "$APP"

# The app is signed, but by nobody in particular, so macOS would rather refuse
# it than ask. Clearing the download flag is the whole of what the right-click
# dance used to do.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo
echo "Installed. Point at the notch — the panel comes down."
echo "It has no window and no Dock icon; its menu is the tray icon at the top right."
