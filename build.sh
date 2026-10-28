#!/bin/bash
# Builds "Derby Check-In.app" and "Derby Web Check In.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# make_app <app name> <executable> <Info.plist> <icon .icns>
make_app() {
    local app="build/$1.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp ".build/release/$2" "$app/Contents/MacOS/"
    cp "$3" "$app/Contents/Info.plist"
    cp "$4" "$app/Contents/Resources/"
    echo "$app"
}

APP=$(make_app "Derby Check-In" DerbyCheckIn Info.plist Resources/AppIcon.icns)
codesign --force --sign - "$APP"
echo "Built $APP"

WEB=$(make_app "Derby Web Check In" DerbyWebCheckIn Info-Web.plist Resources/WebAppIcon.icns)
cp -R Sources/DerbyWebCheckIn/Web "$WEB/Contents/Resources/Web"
codesign --force --sign - "$WEB"
echo "Built $WEB"
