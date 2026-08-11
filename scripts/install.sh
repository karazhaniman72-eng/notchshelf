#!/bin/bash
# Installs the latest released NotchShelf.app into /Applications.
#
# Meant to be run by somebody who has never opened a terminal for anything else:
#   curl -fsSL https://raw.githubusercontent.com/karazhaniman72-eng/notchshelf/main/scripts/install.sh | bash
#
# It downloads the newest build, unpacks it, strips the quarantine flag macOS
# puts on anything downloaded, and opens the app. Nothing else is touched and
# nothing is left behind.
set -e

REPO="${NOTCHSHELF_REPO:-karazhaniman72-eng/notchshelf}"
APP="/Applications/NotchShelf.app"

# Said plainly here rather than left to the launch failure, which on an Intel
# Mac is a dialog that does not explain itself.
if [ "$(uname -m)" != "arm64" ]; then
    echo "This build is for Macs with an Apple chip (M1 and later) and this one"
    echo "has an Intel processor. Building from source works: see the repository."
    exit 1
fi

if [ ! -w /Applications ]; then
    echo "/Applications is not writable by this account — ask an administrator,"
    echo "or drag the app there yourself after downloading it."
    exit 1
fi

echo "Looking for the newest NotchShelf..."

# A release is the tidier home for a build, so it wins when there is one. Until
# then the same zip is committed to the repository and served from there, which
# keeps this one line working the day it is pasted.
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | grep '"browser_download_url"' | grep '\.zip"' | head -1 \
    | cut -d'"' -f4)

if [ -z "$URL" ]; then
    URL="https://raw.githubusercontent.com/$REPO/main/download/NotchShelf.zip"
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

# A running copy cannot be replaced underneath itself. Killed by name rather
# than asked to quit over AppleScript: asking would put an Automation permission
# prompt in front of somebody who is one paste into their first install.
pkill -x NotchShelf 2>/dev/null || true
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
