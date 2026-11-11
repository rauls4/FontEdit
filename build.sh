#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./fetch-resources.sh
arch="$(uname -m)"
bundle="build/FontEdit.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp Resources/Info.plist "$bundle/Contents/"
cp Resources/Default.fnt Resources/Atari.pal "$bundle/Contents/Resources/"
xcrun swiftc -module-cache-path build/ModuleCache -O -swift-version 5 -target "${arch}-apple-macosx14.0" \
    Sources/*.swift -o "$bundle/Contents/MacOS/FontEdit"
xattr -d com.apple.FinderInfo "$bundle" 2>/dev/null || true
codesign --force --sign - "$bundle"
printf '%s\n' "$PWD/$bundle"
