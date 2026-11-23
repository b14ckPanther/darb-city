#!/bin/sh
# Fetch Darb's three typefaces from the official google/fonts repository and write the static
# faces the app bundles: Heebo for Hebrew, Cairo for Arabic, Ubuntu for English and for figures.
#
# Heebo and Cairo are published there as variable fonts only, so their static weights are cut from
# the variable file with fontTools. Ubuntu is published as static files and is copied as it is.
# Cairo's line height is brought in line with the other two (see below); nothing else about any face is changed.
# Each family's licence is bundled beside it: the SIL Open Font Licence for Heebo and Cairo, and the
# Ubuntu Font Licence for Ubuntu.
#
# Usage: scripts/fetch-fonts.sh        (needs python3 and a network connection)
set -e
cd "$(dirname "$0")/.."
OUT="Darb/Resources/Fonts"
RAW="https://raw.githubusercontent.com/google/fonts/main"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

get() { curl -fsSL --retry 3 "$RAW/$1" -o "$2"; }

get "ofl/heebo/Heebo%5Bwght%5D.ttf" "$WORK/Heebo.ttf"
get "ofl/heebo/OFL.txt" "$OUT/Heebo-OFL.txt"
get "ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf" "$WORK/Cairo.ttf"
get "ofl/cairo/OFL.txt" "$OUT/Cairo-OFL.txt"
for w in Regular Medium Bold; do get "ufl/ubuntu/Ubuntu-$w.ttf" "$OUT/Ubuntu-$w.ttf"; done
get "ufl/ubuntu/UFL.txt" "$OUT/Ubuntu-UFL.txt"

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet fonttools
"$WORK/venv/bin/python" - "$WORK" "$OUT" <<'PY'
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

work, out = sys.argv[1], sys.argv[2]
weights = {"Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Black": 900}

def name(font, family, style):
    """Give the static face its own names, so each weight can be asked for by name."""
    table = font["name"]
    ps = f"{family}-{style}"
    for record in list(table.names):
        if record.nameID in (1, 16):
            table.setName(family if record.nameID == 16 else f"{family} {style}", record.nameID, record.platformID, record.platEncID, record.langID)
        elif record.nameID in (2, 17):
            table.setName(style if record.nameID == 17 else "Regular", record.nameID, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 4:
            table.setName(f"{family} {style}", 4, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 6:
            table.setName(ps, 6, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 3:
            table.setName(f"Darb;{ps}", 3, record.platformID, record.platEncID, record.langID)
    for nid, value in ((16, family), (17, style)):
        table.setName(value, nid, 3, 1, 0x409)
    font["OS/2"].usWeightClass = weights[style]

for family in ("Heebo", "Cairo"):
    for style, weight in weights.items():
        font = TTFont(f"{work}/{family}.ttf")
        axes = {"wght": weight}
        if any(a.axisTag == "slnt" for a in font["fvar"].axes):
            axes["slnt"] = 0
        static = instantiateVariableFont(font, axes)
        name(static, family, style)
        if family == "Cairo":
            # Cairo leaves far more room above and below a line than Heebo and Ubuntu do, which makes every
            # Arabic row taller than the same row in the other two languages. Its line is brought to the same
            # proportion (about 1.5 of the size); the letters themselves are untouched.
            static["hhea"].ascent, static["hhea"].descent, static["hhea"].lineGap = 1060, -450, 0
            os2 = static["OS/2"]
            os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = 1060, -450, 0
        static.save(f"{out}/{family}-{style}.ttf")
        print(f"{family}-{style}.ttf")
PY
ls -l "$OUT"
