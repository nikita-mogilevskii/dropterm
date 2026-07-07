#!/bin/bash
# Builds DropTerm.app without Xcode: SwiftPM release build + manual bundle + ad-hoc sign.
set -euo pipefail
cd "$(dirname "$0")"

# --product DropTerm: the test target cannot compile in release (@testable needs testability)
swift build -c release --product DropTerm

APP="build/DropTerm.app"
BIN="$(swift build -c release --product DropTerm --show-bin-path)/DropTerm"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DropTerm"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f "build/AppIcon.icns" ]; then
    cp "build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP"
echo "Built $APP"
