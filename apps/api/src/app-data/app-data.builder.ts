import { crc32 } from "node:zlib";

/**
 * The whole map for the iPhone app, in the compact shape it reads (apps/ios/scripts/export-data.py writes the
 * same shape into the app's bundle): sectors, kinds and places, then the businesses as columns, one array per
 * field, which the phone reads far faster than thousands of small objects. Opening hours are a table of the
 * distinct weeks, and each business points at its row. A place page's details travel alongside, by id.
 */

export const LANGS = ["he", "ar", "en"] as const;
type Lang = (typeof LANGS)[number];
export type Tri = Record<Lang, string>;

/** The town the app opens on until the person chooses one or shares their location. */
const DEFAULT_PLACE = "sakhnin";

/** The usual week of each sector, for a business with no hours of its own; the app labels these as samples. */
const SAMPLE_WEEK: Record<string, [string, string, string]> = {
  food: ["0123456", "11:00", "23:00"],
  beauty: ["012346", "09:00", "20:00"],
  health: ["012346", "08:00", "20:00"],
  sports: ["0123456", "07:00", "22:00"],
  kids: ["01234", "07:30", "16:00"],
  education: ["012346", "08:00", "15:00"],
  tech: ["01234", "09:00", "18:00"],
  services: ["012346", "08:00", "18:00"],
  home: ["012346", "09:00", "19:00"],
  industry: ["01234", "07:00", "16:00"],
  auto: ["012346", "08:00", "17:00"],
  agriculture: ["012346", "07:00", "16:00"],
  events: ["0123456", "10:00", "22:00"],
  travel: ["0123456", "08:00", "20:00"],
  retail: ["0123456", "09:00", "21:00"],
  faith: ["0123456", "05:00", "21:00"],
  civic: ["01234", "08:00", "16:00"],
  community: ["01234", "09:00", "17:00"],
};

/** Words the app's own copy never uses: a line that carries one is left out, and the app falls back to the kind. */
const BANNED = new RegExp(
  "חלאל|(?<![א-ת])כשר(?![א-ת])|ערבי|עברי|דרוזי|מוסלמי|יהודי|נוצרי|לבנוני" +
    "|حلال|كوشير|كاشير|عربي|عبري|درزي|مسلم|إسلامي|يهودي|مسيحي|لبناني" +
    "|halal|kosher|arab|hebrew|druze|muslim|islamic|jewish|christian|lebanese",
  "i",
);

/** The attributes and links the app shows. */
const ATTRIBUTES = new Set([
  "bankCode",
  "branchCode",
  "fuelAdminNo",
  "motGarageType",
  "motGarageId",
  "eduSymbol",
  "delivers",
  "takeaway",
  "wheelchair",
  "outdoorSeating",
  "vegan",
  "vegetarian",
]);
const LINKS = new Set(["instagram", "facebook", "tiktok"]);

export interface SectorRow {
  slug: string;
  name: unknown;
  accent: string;
}
export interface KindRow {
  slug: string;
  sector: string;
  name: unknown;
  synonyms: unknown;
}
export interface PlaceRow {
  slug: string;
  name: unknown;
  aliases: string[];
  lat: number;
  lng: number;
  type: string;
  status: string;
}
export interface BusinessRow {
  slug: string;
  place: string;
  kind: string;
  name: unknown;
  tagline: unknown;
  lat: number;
  lng: number;
  hours: unknown;
  address: unknown;
  phone: string | null;
  whatsapp: string | null;
  website: string | null;
  attributes: unknown;
  links: unknown;
}

/** A text in the three languages; a missing language falls back to Hebrew, then to any. */
export function tri(value: unknown): Tri {
  const v = (value && typeof value === "object" ? value : {}) as Partial<Record<Lang, unknown>>;
  const s = (x: unknown) => (typeof x === "string" ? x : "");
  const base = s(v.he) || s(v.ar) || s(v.en);
  return {
    he: (s(v.he) || base).trim(),
    ar: (s(v.ar) || base).trim(),
    en: (s(v.en) || base).trim(),
  };
}

/** No dashes in copy: a dash between two words becomes a space, between two times it stays. */
export function clean(text: string): string {
  return text.replace(/\s+[-–—]\s+/g, " ").replace(/[–—]/g, "-");
}

/** The week as {"0": [["08:00", "17:00"]]}; null when there are no hours. */
export function week(hours: unknown): Record<string, [string, string][]> | null {
  const weekly = ((hours && typeof hours === "object"
    ? (hours as { weekly?: unknown }).weekly
    : null) ?? {}) as Record<string, unknown>;
  const out: Record<string, [string, string][]> = {};
  for (const [day, spans] of Object.entries(weekly)) {
    if (!Array.isArray(spans)) continue;
    const pairs = spans
      .filter(
        (s): s is { open: string; close: string } =>
          !!s && typeof s.open === "string" && typeof s.close === "string" && !!s.open && !!s.close,
      )
      .map((s) => [s.open, s.close] as [string, string]);
    if (pairs.length) out[String(Number(day))] = pairs;
  }
  return Object.keys(out).length ? out : null;
}

function sampleWeek(sector: string): Record<string, [string, string][]> {
  const [days, open, close] = SAMPLE_WEEK[sector] ?? ["012346", "09:00", "18:00"];
  return Object.fromEntries([...days].map((d) => [d, [[open, close]]]));
}

/** A number that stays the same from one export to the next (the same as the bundled data's), so kept places survive. */
export function businessId(place: string, slug: string, taken: Set<number>): number {
  let key = `${place}/${slug}`;
  let n = crc32(Buffer.from(key, "utf8")) & 0x7fffffff;
  while (taken.has(n) || n === 0) {
    key += "+";
    n = crc32(Buffer.from(key, "utf8")) & 0x7fffffff;
  }
  taken.add(n);
  return n;
}

/** JSON with its keys sorted, as the hours table is keyed. */
function stable(value: Record<string, [string, string][]>): string {
  return JSON.stringify(
    Object.keys(value)
      .sort()
      .map((k) => [k, value[k]]),
  );
}

export function buildAppData(input: {
  sectors: SectorRow[];
  kinds: KindRow[];
  places: PlaceRow[];
  businesses: BusinessRow[];
  generated: Date;
}) {
  const kindSector = new Map(input.kinds.map((k) => [k.slug, k.sector]));
  const kindIndex = new Map(input.kinds.map((k, i) => [k.slug, i]));
  const placeOf = new Map(input.places.map((p) => [p.slug, p]));
  const listings = input.businesses
    .filter((b) => kindSector.has(b.kind) && placeOf.has(b.place))
    .sort((a, b) =>
      a.place === b.place
        ? a.slug < b.slug
          ? -1
          : a.slug > b.slug
            ? 1
            : 0
        : a.place < b.place
          ? -1
          : 1,
    );
  const used = new Set(listings.map((b) => b.place));
  // every town the app can stand in: every city, town and village, with or without businesses yet,
  // and any other place that has one
  const settled = new Set(["city", "town", "village"]);
  const places = input.places
    .filter((p) => settled.has(p.type) || used.has(p.slug))
    .sort((a, b) => (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0));
  const placeIndex = new Map(places.map((p, i) => [p.slug, i]));

  const hoursTable: Record<string, [string, string][]>[] = [];
  const hoursIndex = new Map<string, number>();
  const hoursRow = (value: Record<string, [string, string][]>) => {
    const key = stable(value);
    let i = hoursIndex.get(key);
    if (i === undefined) {
      i = hoursTable.length;
      hoursIndex.set(key, i);
      hoursTable.push(value);
    }
    return i;
  };

  const tags: Record<Lang, string[]> = { he: [""], ar: [""], en: [""] };
  const tagIndex = new Map<string, number>([["", 0]]);
  const tagRow = (value: unknown) => {
    const t0 = tri(value);
    const t = { he: clean(t0.he), ar: clean(t0.ar), en: clean(t0.en) };
    if (!t.he || LANGS.some((l) => BANNED.test(t[l]))) return 0;
    const key = LANGS.map((l) => t[l]).join("\u0001");
    let i = tagIndex.get(key);
    if (i === undefined) {
      i = tags.he.length;
      tagIndex.set(key, i);
      for (const l of LANGS) tags[l].push(t[l]);
    }
    return i;
  };

  const cols = {
    id: [] as number[],
    kind: [] as number[],
    place: [] as number[],
    lat: [] as number[],
    lng: [] as number[],
    hours: [] as number[],
    demo: [] as number[],
    tag: [] as number[],
    name: { he: [] as string[], ar: [] as string[], en: [] as string[] },
  };
  const details: Record<string, Record<string, unknown>> = {};
  const taken = new Set<number>();
  const round5 = (n: number) => Math.round(n * 1e5) / 1e5;

  for (const b of listings) {
    const id = businessId(b.place, b.slug, taken);
    const name = tri(b.name);
    const real = week(b.hours);
    cols.id.push(id);
    cols.kind.push(kindIndex.get(b.kind)!);
    cols.place.push(placeIndex.get(b.place)!);
    cols.lat.push(round5(b.lat));
    cols.lng.push(round5(b.lng));
    cols.hours.push(hoursRow(real ?? sampleWeek(kindSector.get(b.kind)!)));
    cols.demo.push(real ? 0 : 1);
    cols.tag.push(tagRow(b.tagline));
    for (const l of LANGS) cols.name[l].push(name[l]);

    const d: Record<string, unknown> = {};
    if (b.phone) d.phone = b.phone;
    if (b.whatsapp) d.wa = b.whatsapp;
    if (b.website) d.web = b.website;
    const address = tri(b.address);
    const town = tri(placeOf.get(b.place)!.name);
    if (
      address.he &&
      address.he !== town.he &&
      !BANNED.test(LANGS.map((l) => address[l]).join(" "))
    ) {
      // a street given only in Hebrew stays as it is written, in every language
      d.addr = Object.fromEntries(
        LANGS.map((l) => [l, address[l] === town[l] ? address.he : address[l]]),
      );
    }
    const attrs = Object.fromEntries(
      Object.entries((b.attributes ?? {}) as Record<string, unknown>).filter(
        ([k, v]) => ATTRIBUTES.has(k) && v !== null && v !== false && v !== "",
      ),
    );
    if (Object.keys(attrs).length) d.attr = attrs;
    const links = Object.fromEntries(
      Object.entries((b.links ?? {}) as Record<string, unknown>).filter(
        ([k, v]) => LINKS.has(k) && !!v,
      ),
    );
    if (Object.keys(links).length) d.links = links;
    if (Object.keys(d).length) details[String(id)] = d;
  }

  const synonyms = (s: unknown) => {
    const v = (s && typeof s === "object" ? s : {}) as Partial<Record<Lang, unknown>>;
    return Object.fromEntries(LANGS.map((l) => [l, Array.isArray(v[l]) ? v[l] : []]));
  };

  return {
    version: 2,
    generated: input.generated.toISOString().slice(0, 10),
    home: DEFAULT_PLACE,
    sectors: input.sectors.map((s) => ({ slug: s.slug, name: tri(s.name), accent: s.accent })),
    kinds: input.kinds.map((k) => ({
      slug: k.slug,
      sector: k.sector,
      name: tri(k.name),
      syn: synonyms(k.synonyms),
    })),
    places: places.map((p) => ({
      slug: p.slug,
      name: tri(p.name),
      aliases: p.aliases ?? [],
      lat: round5(p.lat),
      lng: round5(p.lng),
      type: p.type,
    })),
    hours: hoursTable,
    tags,
    businesses: cols,
    details,
  };
}
