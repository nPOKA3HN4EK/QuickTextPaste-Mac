#!/bin/bash
# Собирает build/QuickTextPaste.app
set -euo pipefail
cd "$(dirname "$0")"

APP=build/QuickTextPaste.app
mkdir -p build
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
    Sources/*.swift -o "$APP/Contents/MacOS/QuickTextPaste"

cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    swift make_icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Готово: $(pwd)/$APP"
