#!/bin/sh
# Build Darb, install it on the simulator and launch it.
# Usage: scripts/run.sh [HH:MM] [extra args...]
#   scripts/run.sh 20:30                         night
#   scripts/run.sh 09:18 -darbLangOnce ar        day, in Arabic
#   scripts/run.sh 20:30 -darbOnboard YES        with the first run
# DARB_SIM picks the simulator (default "iPhone 17 Pro Max").
set -e
cd "$(dirname "$0")/.."
DEVICE="${DARB_SIM:-iPhone 17 Pro Max}"
UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcodegen generate --quiet
xcodebuild -project Darb.xcodeproj -scheme Darb -destination "id=$UDID" -derivedDataPath build -quiet build
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/Darb.app
xcrun simctl terminate "$UDID" il.co.darb.app 2>/dev/null || true
TIME="$1"; [ $# -gt 0 ] && shift
if [ -n "$TIME" ]; then
  xcrun simctl launch "$UDID" il.co.darb.app -darbTime "$TIME" "$@"
else
  xcrun simctl launch "$UDID" il.co.darb.app "$@"
fi
