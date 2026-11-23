#!/bin/sh
# Time, from the tap to the first frame, the screens people open most. Prints one line per screen.
#
#   scripts/perf.sh                 on the iPhone 17 Pro Max simulator (the build must be installed: scripts/run.sh)
#   scripts/perf.sh phone           on the connected iPhone, which must be unlocked, with the build installed
#
# Each run starts the app, lets the home screen settle for 2.5 s, opens one screen and reads the app's own
# timing (`-darbPerf YES`, see Darb/Data/Perf.swift):
#   shown <screen>  <ms from the tap to the first frame>  (built in <ms until the screen's content exists>)
# The same numbers are signposts in Instruments (Points of Interest, "tap to frame").
PHONE="${DARB_PHONE:-00008130-00112D500E02001C}"
DEVICE="${DARB_SIM:-iPhone 17 Pro Max}"
OUT=$(mktemp)
run() {
  name="$1"; shift
  : > "$OUT"
  if [ "$TARGET" = phone ]; then
    (cd /tmp && xcrun devicectl device process launch --console --terminate-existing --device "$PHONE" il.co.darb.app -- -darbPerf YES -darbOnboarded YES "$@" > "$OUT" 2>&1 &)
    sleep 9; pkill -f "devicectl device process launch" 2>/dev/null
  else
    UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
    xcrun simctl terminate "$UDID" il.co.darb.app 2>/dev/null; sleep 0.5
    (xcrun simctl launch --console-pty "$UDID" il.co.darb.app -darbPerf YES -darbOnboarded YES "$@" > "$OUT" 2>&1 &)
    sleep 7; xcrun simctl terminate "$UDID" il.co.darb.app 2>/dev/null
  fi
  if grep -aq "Locked" "$OUT"; then echo "The phone is locked. Unlock it and run again."; exit 1; fi
  line=$(grep -a "PERF shown" "$OUT" | head -1 | sed 's/PERF shown //')
  printf '%-22s %s\n' "$name" "${line:-no timing (did the screen open?)}"
}
TARGET="$1"
run "launch to ready"      -darbSkipSplash YES
grep -a "PERF work" "$OUT" | grep -E "data.decode|store.install|store.measure" | sed 's/PERF work/   /'
run "need (food)"          -darbSkipSplash YES -darbRoute need:food
run "kind (kindergartens)" -darbSkipSplash YES -darbRoute kind:kindergartens
run "one place"            -darbSkipSplash YES -darbRoute business:1419998672
run "search"               -darbSheet search
run "town picker"          -darbSheet town
run "menu"                 -darbSheet menu
run "settings"             -darbSheet settings
run "everything else"      -darbSheet kinds
rm -f "$OUT"
