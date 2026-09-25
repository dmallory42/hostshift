#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
OUTPUT_DIR="${HOSTSHIFT_BUILD_DIR:-$PWD/build}"
APP="$OUTPUT_DIR/Hostshift.app"
MODULES="$OUTPUT_DIR/modules"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons" "$MODULES"
ARCH=$(uname -m)
TARGET="$ARCH-apple-macosx14.0"
# Direct swiftc also works with Command Line Tools installations without Xcode.
swiftc -swift-version 6 -target "$TARGET" -O -parse-as-library \
    -emit-module -emit-object -whole-module-optimization -module-name HostsCore \
    Sources/HostsCore/*.swift -o "$MODULES/HostsCore.o" \
    -emit-module-path "$MODULES/HostsCore.swiftmodule"
swiftc -swift-version 6 -target "$TARGET" -O -parse-as-library \
    -I "$MODULES" Sources/Hostshift/*.swift "$MODULES/HostsCore.o" \
    -o "$APP/Contents/MacOS/Hostshift"
swiftc -swift-version 6 -target "$TARGET" -O -parse-as-library \
    -I "$MODULES" Sources/HostshiftHelper/*.swift "$MODULES/HostsCore.o" \
    -o "$APP/Contents/MacOS/HostshiftHelper"
cp Resources/local.hostshift.helper.plist "$APP/Contents/Library/LaunchDaemons/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${HOSTSHIFT_UPDATE_REPOSITORY:-}" ]]; then
    plutil -replace HostshiftUpdateRepository -string "$HOSTSHIFT_UPDATE_REPOSITORY" "$APP/Contents/Info.plist"
fi
if [[ -n "${HOSTSHIFT_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$HOSTSHIFT_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${HOSTSHIFT_BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$HOSTSHIFT_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
swift scripts/icon.swift "$OUTPUT_DIR"
iconutil -c icns "$OUTPUT_DIR/Hostshift.iconset" -o "$APP/Contents/Resources/Hostshift.icns"
SIGNING_IDENTITY="${HOSTSHIFT_SIGNING_IDENTITY:--}"
codesign --force --options runtime --identifier local.hostshift.helper --sign "$SIGNING_IDENTITY" "$APP/Contents/MacOS/HostshiftHelper"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP"
printf 'Built %s\n' "$APP"
