#!/bin/sh
# Records Instruments' Animation Hitches on the connected iPhone while Darb opens a category page and closes it,
# then prints every hitch table it found. The phone must be unlocked, with a Release build installed.
#   scripts/hitches.sh [route]        default route: need:sweets
set -e
cd "$(dirname "$0")/.."
PHONE="${DARB_PHONE:-00008130-00112D500E02001C}"
ROUTE="${1:-need:sweets}"
OUT="${TMPDIR:-.}/darb-hitches.trace"
rm -rf "$OUT"
xcrun xctrace record --template 'Animation Hitches' --device "$PHONE" --time-limit 10s --output "$OUT" \
  --launch -- il.co.darb.app -darbOnboarded YES -darbRoute "$ROUTE" -darbAutoBack 2.5
for schema in $(xcrun xctrace export --input "$OUT" --toc | grep -o 'schema="[a-z-]*hitch[a-z-]*"' | sort -u | sed 's/schema="//;s/"//'); do
  ROWS=$(xcrun xctrace export --input "$OUT" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$schema\"]" | grep -c '<row' || true)
  echo "$schema: $ROWS rows"
done
echo "Open it in Instruments for the frame by frame view: open $OUT"
