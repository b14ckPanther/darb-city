#!/usr/bin/env python3
"""Write the businesses the app bundles from Darb's live map (GET /app/data), the same database the website and
the admin use. The app fetches the map again when it opens; this copy is only what a new install starts with.

    python3 scripts/pull-data.py          (run from apps/ios, or from anywhere)

It writes darb.json, needs.json (the nine everyday needs, for the widget and Siri) and details.json into
Darb/Resources/Data. promo.json and screens.json still come from scripts/export-data.py.
"""
import gzip
import json
import os
import sys
import urllib.request

API = os.environ.get("DARB_API", "https://api.darb.co.il")
here = os.path.dirname(os.path.abspath(__file__))
out = os.path.normpath(os.path.join(here, "..", "Darb", "Resources", "Data"))
# the kinds behind the nine everyday needs (Darb/Data/Needs.swift)
NEED_KINDS = {"restaurants", "grill", "hummus", "sweets", "ice-cream", "cafes", "bakeries", "pharmacies", "shops",
              "stations", "garages", "banks"}

req = urllib.request.Request(API + "/app/data", headers={"Accept-Encoding": "gzip", "User-Agent": "darb-ios-build"})
raw = urllib.request.urlopen(req, timeout=60).read()
try:
    raw = gzip.decompress(raw)
except OSError:
    pass
data = json.loads(raw)
details = data.pop("details")
cols = data["businesses"]
keep = [i for i, k in enumerate(cols["kind"]) if data["kinds"][k]["slug"] in NEED_KINDS]
needs = dict(data)
needs["businesses"] = {key: ({lang: [v[lang][i] for i in keep] for lang in v} if isinstance(v, dict) else [v[i] for i in keep])
                       for key, v in cols.items()}
sizes = {}
for name, value in (("darb.json", data), ("needs.json", needs), ("details.json", details)):
    path = os.path.join(out, name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
    sizes[name] = os.path.getsize(path)
json.dump({"businesses": len(cols["id"]), "needsPlaces": len(keep), "places": len(data["places"]), "bytes": sizes},
          sys.stdout, indent=1)
print()
