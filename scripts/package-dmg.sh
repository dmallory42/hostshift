#!/bin/bash
# Packages a built Hostshift.app into a drag-to-Applications disk image.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
APP="${1:?Usage: scripts/package-dmg.sh path/to/Hostshift.app [output.dmg]}"
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
OUTPUT="${2:-$(dirname "$APP")/Hostshift-$VERSION.dmg}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/hostshift-dmg.XXXXXX")
trap 'hdiutil detach "$WORK/mount" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

mkdir -p "$WORK/stage/.background"
ditto "$APP" "$WORK/stage/Hostshift.app"
ln -s /Applications "$WORK/stage/Applications"
swift scripts/dmg-background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/stage/.background/background.tiff" >/dev/null 2>&1

hdiutil create -quiet -srcfolder "$WORK/stage" -volname Hostshift -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$WORK/mount" "$WORK/rw.dmg"
# Finder saves the window layout in the volume's .DS_Store.
osascript <<OSA
tell application "Finder"
    set vol to (POSIX file "$WORK/mount") as alias
    open vol
    set win to container window of vol
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    set bounds of win to {200, 120, 800, 548}
    set opts to icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff" of vol
    set position of item "Hostshift.app" of vol to {150, 190}
    set position of item "Applications" of vol to {450, 190}
    update vol without registering applications
    delay 1
    close win
end tell
OSA
sync
hdiutil detach -quiet "$WORK/mount"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUTPUT"
if [[ -n "${HOSTSHIFT_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$HOSTSHIFT_SIGNING_IDENTITY" "$OUTPUT"
fi
printf 'Packaged %s\n' "$OUTPUT"
