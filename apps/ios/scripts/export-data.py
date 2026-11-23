#!/usr/bin/env python3
"""Write the data the iPhone app bundles, from packages/seed/data.

Every real business in the north goes in, in Hebrew, Arabic and English, with its coordinates. The app
works out kilometres and minutes on the phone, from where the person is, so nothing here is measured
from any one town.

    python3 scripts/export-data.py          (run from apps/ios, or from anywhere)

It writes five files into Darb/Resources/Data:

  darb.json     Read when the app opens. Sectors, kinds and places, then the businesses as columns
                (one array per field, all the same length), which the phone reads far faster than
                thirteen thousand small objects. Opening hours are a table of the distinct weeks,
                and each business points at its row.
  needs.json    The same shape as darb.json, with only the places of the nine everyday needs. The widget
                and Siri read this one: it is a third of the size, and they ask about nothing else.
  details.json  Read the first time a place's page opens: phone, WhatsApp, website, address,
                attributes and social links, by business id.
  screens.json  The sample page of each kind (menu, prices, services). Read only when a sample page
                is shown, and always labelled as a sample there.
  promo.json    Darb's plans with their features, prices and notes, the pricing page's copy, the
                paid placements (none are sold yet) and the profiles of Darb's real clients.

What goes in, and what does not:

  listings/*.json   every business, from public open data. All of them are real.
  clients.json      Darb's real clients. A client that is already in the listings keeps the listing
                    and gains a profile; one that is not is added as a business of its own.
  businesses.json   the showroom examples. They are made up to show what a page can look like, so
                    they are read only to be counted and are never put in the app.

Opening hours. Most public sources give no hours. A business without hours of its own is given the
usual week of its sector and marked `demo`, and the app labels those hours as sample hours wherever it
shows them. A business with hours of its own is never marked.
"""
import datetime
import json
import os
import re
import sys
import zlib

here = os.path.dirname(os.path.abspath(__file__))
seed = os.path.normpath(os.path.join(here, "..", "..", "..", "packages", "seed", "data"))
out = os.path.normpath(os.path.join(here, "..", "Darb", "Resources", "Data"))
LANGS = ("he", "ar", "en")

# The town the app opens on until the person chooses one or shares their location.
DEFAULT_PLACE = "sakhnin"

# The usual week of each sector, for a business whose source gives no hours: (days, open, close),
# day 0 is Sunday. These are sample hours and are labelled as such in the app.
SAMPLE_WEEK = {
    "food": ("0123456", "11:00", "23:00"),
    "beauty": ("012346", "09:00", "20:00"),
    "health": ("012346", "08:00", "20:00"),
    "sports": ("0123456", "07:00", "22:00"),
    "kids": ("01234", "07:30", "16:00"),
    "education": ("012346", "08:00", "15:00"),
    "tech": ("01234", "09:00", "18:00"),
    "services": ("012346", "08:00", "18:00"),
    "home": ("012346", "09:00", "19:00"),
    "industry": ("01234", "07:00", "16:00"),
    "auto": ("012346", "08:00", "17:00"),
    "agriculture": ("012346", "07:00", "16:00"),
    "events": ("0123456", "10:00", "22:00"),
    "travel": ("0123456", "08:00", "20:00"),
    "retail": ("0123456", "09:00", "21:00"),
    "faith": ("0123456", "05:00", "21:00"),
    "civic": ("01234", "08:00", "16:00"),
    "community": ("01234", "09:00", "17:00"),
}

# Words the app's own copy never uses. A tagline or a client's line that carries one is left out,
# and the app falls back to the kind's name.
BANNED = re.compile(
    "חלאל|(?<![א-ת])כשר(?![א-ת])|ערבי|עברי|דרוזי|מוסלמי|יהודי|נוצרי|לבנוני"
    "|حلال|كوشير|كاشير|عربي|عبري|درزي|مسلم|إسلامي|يهودي|مسيحي|لبناني"
    "|halal|kosher|arab|hebrew|druze|muslim|islamic|jewish|christian|lebanese",
    re.IGNORECASE,
)

# The kinds behind the nine everyday needs on the home screen (Darb/Data/Needs.swift). needs.json holds only
# their places, for the widget and Siri, which answer nothing else and must stay light.
NEED_KINDS = {"restaurants", "grill", "hummus", "sweets", "ice-cream", "cafes", "bakeries", "pharmacies", "shops",
              "stations", "garages", "banks"}

# The attributes and links the app shows.
ATTRIBUTES = ("bankCode", "branchCode", "fuelAdminNo", "motGarageType", "motGarageId", "eduSymbol",
              "delivers", "takeaway", "wheelchair", "outdoorSeating", "vegan", "vegetarian")
LINKS = ("instagram", "facebook", "tiktok")


def load(name):
    with open(os.path.join(seed, name), encoding="utf-8") as f:
        return json.load(f)


def tri(value):
    """A text in the three languages; a missing language falls back to Hebrew, then to any."""
    value = value or {}
    base = value.get("he") or value.get("ar") or value.get("en") or ""
    return {lang: (value.get(lang) or base).strip() for lang in LANGS}


def clean(text):
    """No dashes in copy: a dash between two words becomes a space, between two times it stays."""
    return re.sub(r"\s+[-–—]\s+", " ", text).replace("–", "-").replace("—", "-")


def week(hours):
    """The seed's week as {"0": [["08:00", "17:00"]]}; None when the source gives no hours."""
    weekly = (hours or {}).get("weekly") or {}
    result = {}
    for day, spans in weekly.items():
        pairs = [[s["open"], s["close"]] for s in spans if s.get("open") and s.get("close")]
        if pairs:
            result[str(int(day))] = pairs
    return result or None


def sample_week(sector):
    days, open_, close = SAMPLE_WEEK.get(sector, ("012346", "09:00", "18:00"))
    return {d: [[open_, close]] for d in days}


def business_id(place, slug, taken):
    """A number that stays the same from one export to the next, so kept places and links survive."""
    key = f"{place}/{slug}"
    n = zlib.crc32(key.encode("utf-8")) & 0x7FFFFFFF
    while n in taken or n == 0:
        key += "+"
        n = zlib.crc32(key.encode("utf-8")) & 0x7FFFFFFF
    taken.add(n)
    return n


def km(a_lat, a_lng, b_lat, b_lng):
    import math
    return math.hypot((a_lat - b_lat) * 111.2, (a_lng - b_lng) * 93.4)


def build():
    sectors_raw = load("sectors.json")
    kinds_raw = [k for k in load("kinds.json") if k.get("status", "active") == "active"]
    places_raw = load("places.json")
    plans_raw = load("plans.json")
    texts_raw = load("texts.json")
    clients = load("clients.json")
    screens_raw = {**load("screens.json"), **load("extra-screens.json")}
    showroom = len(load("businesses.json"))

    kind_sector = {k["slug"]: k["sector"] for k in kinds_raw}
    sources = []
    listings = []
    for name in sorted(os.listdir(os.path.join(seed, "listings"))):
        if not name.endswith(".json"):
            continue
        data = load(os.path.join("listings", name))
        src = data.get("source") or {}
        sources.append({"file": name, "name": src.get("name"), "url": src.get("url"),
                        "fetched": src.get("fetched"), "count": len(data["businesses"])})
        listings += data["businesses"]

    # A client already in the listings keeps the listing; the others are added.
    def listing_of(client):
        best = None
        for i, b in enumerate(listings):
            if b["name"]["he"] != client["name"]["he"]:
                continue
            d = km(b["lat"], b["lng"], client["lat"], client["lng"])
            if d < 0.3 and (best is None or d < best[0]):
                best = (d, i)
        return None if best is None else best[1]

    client_rows = {}
    for c in clients["businesses"]:
        i = listing_of(c)
        if i is None:
            listings.append(c)
            i = len(listings) - 1
        client_rows[c["slug"]] = i

    listings = [b for b in listings if b.get("primaryKind") in kind_sector]
    place_of = {p["slug"]: p for p in places_raw}
    used_places = {b["place"] for b in listings}
    # Every town the app can stand in: the live ones, and any that has a business.
    places = [p for p in places_raw
              if p.get("lat") is not None and p["type"] not in ("country", "region")
              and (p["status"] == "live" or p["slug"] in used_places)]
    places.sort(key=lambda p: p["slug"])
    place_index = {p["slug"]: i for i, p in enumerate(places)}
    listings = [b for b in listings if b["place"] in place_index]
    kind_index = {k["slug"]: i for i, k in enumerate(kinds_raw)}

    hours_table, hours_index = [], {}

    def hours_row(value):
        key = json.dumps(value, sort_keys=True)
        if key not in hours_index:
            hours_index[key] = len(hours_table)
            hours_table.append(value)
        return hours_index[key]

    tag_table = {lang: [""] for lang in LANGS}
    tag_index = {"": 0}

    def tag_row(value):
        t = {lang: clean(value[lang]) for lang in LANGS}
        if not t["he"] or any(BANNED.search(t[lang]) for lang in LANGS):
            return 0
        key = "\u0001".join(t[lang] for lang in LANGS)
        if key not in tag_index:
            tag_index[key] = len(tag_table["he"])
            for lang in LANGS:
                tag_table[lang].append(t[lang])
        return tag_index[key]

    cols = {"id": [], "kind": [], "place": [], "lat": [], "lng": [], "hours": [], "demo": [], "tag": [],
            "name": {lang: [] for lang in LANGS}}
    details = {}
    taken = set()
    ids = []
    own_hours = 0
    for b in listings:
        bid = business_id(b["place"], b["slug"], taken)
        ids.append(bid)
        name = tri(b["name"])
        real = week(b.get("hours"))
        if real:
            own_hours += 1
        cols["id"].append(bid)
        cols["kind"].append(kind_index[b["primaryKind"]])
        cols["place"].append(place_index[b["place"]])
        cols["lat"].append(round(b["lat"], 5))
        cols["lng"].append(round(b["lng"], 5))
        cols["hours"].append(hours_row(real or sample_week(kind_sector[b["primaryKind"]])))
        cols["demo"].append(0 if real else 1)
        cols["tag"].append(tag_row(tri(b.get("tagline"))))
        for lang in LANGS:
            cols["name"][lang].append(name[lang])

        d = {}
        if b.get("phone"):
            d["phone"] = b["phone"]
        if b.get("whatsapp"):
            d["wa"] = b["whatsapp"]
        if b.get("website"):
            d["web"] = b["website"]
        address = tri(b.get("address"))
        town = tri(place_of[b["place"]]["name"])
        if address["he"] and address["he"] != town["he"] and not BANNED.search(" ".join(address.values())):
            # a street the source gives only in Hebrew stays as it is written, in every language
            d["addr"] = {lang: address["he"] if address[lang] == town[lang] else address[lang] for lang in LANGS}
        attrs = {k: v for k, v in (b.get("attributes") or {}).items() if k in ATTRIBUTES and v not in (None, False, "")}
        if attrs:
            d["attr"] = attrs
        links = {k: v for k, v in (b.get("links") or {}).items() if k in LINKS and v}
        if links:
            d["links"] = links
        if d:
            details[str(bid)] = d

    used_kinds = {listings[i]["primaryKind"] for i in range(len(listings))}

    core = {
        "version": 2,
        "generated": datetime.date.today().isoformat(),
        "home": DEFAULT_PLACE,
        "sectors": [{"slug": s["slug"], "name": tri(s["name"]), "accent": s["accent"]}
                    for s in sorted(sectors_raw, key=lambda s: s.get("order", 0))],
        "kinds": [{"slug": k["slug"], "sector": k["sector"], "name": tri(k["name"]),
                   "syn": {lang: (k.get("synonyms") or {}).get(lang, []) for lang in LANGS}}
                  for k in kinds_raw],
        "places": [{"slug": p["slug"], "name": tri(p["name"]), "aliases": p.get("aliases") or [],
                    "lat": round(p["lat"], 5), "lng": round(p["lng"], 5), "type": p["type"]}
                   for p in places],
        "hours": hours_table,
        "tags": tag_table,
        "businesses": cols,
        "sources": sources,
    }

    # the same shape as darb.json, with only the rows of the everyday needs
    keep = [i for i, k in enumerate(cols["kind"]) if kinds_raw[k]["slug"] in NEED_KINDS]
    needs = dict(core)
    needs.pop("sources")
    needs["businesses"] = {key: ({lang: [value[lang][i] for i in keep] for lang in LANGS} if key == "name" else [value[i] for i in keep])
                           for key, value in cols.items()}

    def screen(s):
        def text(v):
            t = tri(v)
            return {lang: clean(t[lang]) for lang in LANGS}
        return {
            "title": text(s.get("title")),
            "sub": text(s.get("subtitle")) if s.get("subtitle") else None,
            "tags": [text(t) for t in s.get("tags", [])],
            "items": [[text(i.get("label")), text(i.get("meta"))] for i in s.get("items", [])],
            "cta": text(s.get("cta")) if s.get("cta") else None,
        }

    screens = {slug: screen(s) for slug, s in screens_raw.items() if slug in used_kinds}

    # Darb's real clients: each has an app or a system built by Darb, which is the ecosystem plan.
    # No client has given a logo, a cover, photos or a storefront picture yet, and none is ever made up.
    shots = {"caramel": "client-caramel", "raghad": "client-raghad", "paz": "client-paz"}
    profiles = []
    for c in clients["businesses"]:
        i = client_rows.get(c["slug"])
        if i is None or i >= len(ids):
            continue
        e = c.get("experience") or {}
        items = []
        for it in e.get("items", []):
            label, meta = tri(it.get("label")), tri(it.get("meta")) if it.get("meta") else None
            if BANNED.search(" ".join(label.values()) + " " + " ".join((meta or {}).values())):
                continue
            items.append({"label": {k: clean(v) for k, v in label.items()},
                          "meta": {k: clean(v) for k, v in meta.items()} if meta else None})
        tags = [tri(t) for t in e.get("tags", [])]
        tags = [t for t in tags if not BANNED.search(" ".join(t.values()))]
        profiles.append({
            "id": ids[i], "slug": c["slug"], "plan": "ecosystem",
            "logo": None, "cover": None, "photos": [], "storefront": None,
            "app": shots.get(c.get("brand") or ""),
            "menuURL": None, "orderURL": c.get("website"), "bookingURL": None,
            "tagline": tri(c.get("tagline")), "address": tri(c.get("address")),
            "phone": c.get("phone"), "whatsapp": c.get("whatsapp"),
            "palette": e.get("palette"),
            "items": items, "tags": tags,
        })

    def plan(p):
        return {
            "slug": p["slug"], "order": p.get("order", 0), "status": p.get("status", "live"),
            "name": tri(p["name"]), "tagline": tri(p["tagline"]),
            "monthly": p.get("monthly"), "setup": p.get("setup"),
            "priceNote": tri(p["priceNote"]) if p.get("priceNote") else None,
            "features": {lang: (p.get("features") or {}).get(lang, []) for lang in LANGS},
            "highlighted": bool(p.get("highlighted")),
            "cta": tri(p["ctaLabel"]) if p.get("ctaLabel") else None,
        }

    promo = {
        "plans": [plan(p) for p in sorted(plans_raw, key=lambda p: p.get("order", 0))],
        "texts": {t["key"]: tri(t["value"]) for t in texts_raw},
        # Paid placements. None are sold yet, and a sponsor is never made up.
        "sponsorships": [],
        "profiles": profiles,
    }

    os.makedirs(out, exist_ok=True)
    sizes = {}
    for name, value in (("darb.json", core), ("needs.json", needs), ("details.json", details), ("screens.json", screens), ("promo.json", promo)):
        path = os.path.join(out, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
        sizes[name] = os.path.getsize(path)

    report = {
        "businesses": len(ids), "withOwnHours": own_hours, "withSampleHours": len(ids) - own_hours,
        "kinds": len(kinds_raw), "kindsWithBusinesses": len(used_kinds), "places": len(places),
        "placesWithBusinesses": len(used_places & set(place_index)), "hourWeeks": len(hours_table),
        "taglines": len(tag_table["he"]) - 1, "details": len(details), "screens": len(screens),
        "profiles": len(profiles), "plans": len(promo["plans"]), "showroomExamplesLeftOut": showroom, "needsPlaces": len(keep),
        "bytes": sizes,
    }
    return report


if __name__ == "__main__":
    json.dump(build(), sys.stdout, ensure_ascii=False, indent=1)
    print()
