#!/bin/sh
# Launch Darb on the simulator with test arguments and save a screenshot.
# Usage: scripts/shot.sh out.png [HH:MM] [route] [extra args...]
#   scripts/shot.sh home.png 09:18
#   scripts/shot.sh fuel.png 20:30 need:fuel
#   scripts/shot.sh settings.png 20:30 "" -darbSheet settings -darbLangOnce ar
# The first run is skipped unless you pass -darbOnboard YES. DARB_SIM picks the simulator, DARB_WAIT the seconds to wait.
set -e
DEVICE="${DARB_SIM:-iPhone 17 Pro Max}"
UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
OUT="$1"; TIME="${2:-20:30}"; ROUTE="$3"; shift 3 2>/dev/null || shift $#
xcrun simctl terminate "$UDID" il.co.darb.app 2>/dev/null || true
if [ -n "$ROUTE" ]; then
  xcrun simctl launch "$UDID" il.co.darb.app -darbTime "$TIME" -darbOnboarded YES -darbAppearance hour -darbSkipSplash YES -darbRoute "$ROUTE" "$@" >/dev/null
else
  xcrun simctl launch "$UDID" il.co.darb.app -darbTime "$TIME" -darbOnboarded YES -darbAppearance hour "$@" >/dev/null
fi
sleep "${DARB_WAIT:-4}"
xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null 2>&1
echo "$OUT"
