#!/bin/bash
# Builds build/OneHand.app. Run `./build.sh install` to also copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OneHand.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos11.0" \
    -framework Cocoa -framework Carbon \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/OneHand"

cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" # ad-hoc signature so macOS can remember the Accessibility grant
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x OneHand 2>/dev/null || true
    rm -rf "$HOME/Applications/OneHand.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/OneHand.app"
    echo "Installed to ~/Applications/OneHand.app"
fi
