import { fileURLToPath } from "node:url";
import type { LoyaltyCardDto, LoyaltyStandingDto } from "@darb/contracts";
import sharp from "sharp";

export const LANGS = ["he", "ar", "en"] as const;
type Lang = (typeof LANGS)[number];
type Localized = Partial<Record<string, string>>;

const FOREST = "rgb(11,34,25)";
const IVORY = "rgb(251,247,236)";
const MUSTARD = "rgb(255,195,48)";

export interface PassSettings {
  passType: string;
  teamId: string;
  /** Where Wallet registers and asks for updates; null leaves the pass static. */
  serviceUrl: string | null;
  authToken: string;
  /** What the QR holds: the counter's page for this card. */
  scanUrl: string;
}

const pick = (t: Localized, lang: Lang) =>
  [t[lang], t["he"], t["ar"], t["en"]].find((v) => v && v.trim() !== "") ?? "";

/** The most partners the front lists; the back lists them all. */
export const FRONT_ROWS = 4;

/**
 * The partners in the order the front shows them: a reward ready to collect, then the latest stamped, then the
 * offers not yet started, oldest first.
 */
export function ordered(standings: LoyaltyStandingDto[]): LoyaltyStandingDto[] {
  const rank = (s: LoyaltyStandingDto) => (s.ready ? 0 : s.lastStampAt ? 1 : 2);
  return standings
    .map((s, i) => ({ s, i }))
    .sort(
      (a, b) =>
        rank(a.s) - rank(b.s) ||
        (b.s.lastStampAt ?? "").localeCompare(a.s.lastStampAt ?? "") ||
        a.i - b.i,
    )
    .map((x) => x.s);
}

const grouped = (code: string) => `${code.slice(0, 5)} ${code.slice(5)}`;

function more(n: number, lang: Lang) {
  if (lang === "he") return n === 1 ? "עוד חותמת אחת" : `עוד ${n} חותמות`;
  if (lang === "ar") return n === 1 ? "ختم واحد كمان" : `${n} أختام كمان`;
  return n === 1 ? "1 more stamp" : `${n} more stamps`;
}

const COPY: Record<string, Record<Lang, string>> = {
  description: { he: "כרטיס דרב", ar: "بطاقة درب", en: "Darb card" },
  logo: { he: "דרב", ar: "درب", en: "Darb" },
  stamps: { he: "חותמות", ar: "أختام", en: "Stamps" },
  newStamp: { he: "חותמת חדשה: %@", ar: "ختم جديد: %@", en: "New stamp: %@" },
  toGo: { he: "נשאר", ar: "باقي", en: "To go" },
  ready: { he: "מוכן", ar: "جاهزة", en: "Ready" },
  readyValue: {
    he: "מחכה לכם בקופה",
    ar: "بتستناكم عند الصندوق",
    en: "Waiting at the counter",
  },
  offers: { he: "הטבות", ar: "عروض", en: "Offers" },
  partners: { he: "שותפים", ar: "شركاء", en: "Partners" },
  lastStamp: { he: "חותמת אחרונה", ar: "آخر ختم", en: "Last stamp" },
  emptyLabel: { he: "כרטיס דרב", ar: "بطاقة درب", en: "Darb card" },
  emptyValue: { he: "אוספים חותמות", ar: "اجمعوا أختام", en: "Collect stamps" },
  howLabel: { he: "איך", ar: "كيف", en: "How" },
  howValue: {
    he: "מראים את הקוד בקופה",
    ar: "اعرضوا الرمز عند الصندوق",
    en: "Show the code at the counter",
  },
  code: { he: "קוד הכרטיס", ar: "رمز البطاقة", en: "Card code" },
  about: { he: "על הכרטיס", ar: "عن البطاقة", en: "About" },
  aboutValue: {
    he: "כרטיס אחד לכל העסקים בדרב. בכל ביקור בעסק עם הטבה, הצוות סורק את הקוד ומוסיף חותמת. כשהכרטיס מתמלא, ההטבה שלכם.",
    ar: "بطاقة وحدة لكل المصالح بدرب. بكل زيارة لمصلحة فيها عرض، الطاقم بيمسح الرمز وبيزيد ختم. لما تكمل البطاقة، الهدية إلكم.",
    en: "One card for every business on Darb. Each visit to a business with an offer, the staff scan the code and add a stamp. Fill the card and the reward is yours.",
  },
  rewards: { he: "הטבות שנאספו", ar: "هدايا استلمتوها", en: "Rewards collected" },
};

/** pass.strings: "key" = "value"; per line, escaped. */
function strings(entries: Record<string, string>): Buffer {
  const esc = (s: string) => s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
  const body = Object.entries(entries)
    .map(([k, v]) => `"${esc(k)}" = "${esc(v)}";`)
    .join("\n");
  // UTF-16 with a byte order mark, as Wallet's own tools write it
  return Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(body + "\n", "utf16le")]);
}

/**
 * pass.json and its translations. Every text in pass.json is a key that each language's pass.strings fills in, so
 * the one pass reads in Hebrew, Arabic or English, as the phone is set.
 */
export function passContent(card: LoyaltyCardDto, s: PassSettings) {
  const rows = ordered(card.standings);
  const front = rows[0] ?? null;
  const text: Record<Lang, Record<string, string>> = { he: {}, ar: {}, en: {} };
  const put = (key: string, by: (lang: Lang) => string) => {
    for (const lang of LANGS) text[lang][key] = by(lang);
    return key;
  };
  const copy = (name: string) => put(name, (lang) => COPY[name]![lang]);

  const header: object[] = [];
  const primary: object[] = [];
  const secondary: object[] = [];
  const auxiliary: object[] = [];
  const status = (st: LoyaltyStandingDto, l: Lang) =>
    `${pick(st.offer.business.name, l)} · ${Math.min(st.stamps, st.offer.goal)}/${st.offer.goal}`;
  if (rows.length > 1) {
    // several partners: the strip lists them, and the fields say what just happened
    const total = rows.reduce((n, st) => n + Math.min(st.stamps, st.offer.goal), 0);
    header.push({ key: "stamps", label: copy("stamps"), value: total });
    secondary.push(
      front!.ready
        ? {
            key: "state",
            label: copy("ready"),
            value: put(
              "f.ready",
              (l) => `${pick(front!.offer.business.name, l)} · ${pick(front!.offer.reward, l)}`,
            ),
            changeMessage: put("f.changed", () => "%@"),
          }
        : front!.lastStampAt
          ? {
              key: "state",
              label: copy("lastStamp"),
              value: put("f.last", (l) => status(front!, l)),
              changeMessage: copy("newStamp"),
            }
          : { key: "state", label: copy("howLabel"), value: copy("howValue") },
    );
    auxiliary.push({ key: "offers", label: copy("partners"), value: rows.length });
  } else if (front) {
    const o = front.offer;
    header.push({
      key: "stamps",
      label: copy("stamps"),
      value: `${Math.min(front.stamps, o.goal)}/${o.goal}`,
      changeMessage: copy("newStamp"),
    });
    // the strip is the stamps themselves, so nothing is written across it: the offer sits below
    secondary.push({
      key: "offer",
      label: put("f.business", (l) => pick(o.business.name, l)),
      value: put("f.reward", (l) => pick(o.reward, l)),
    });
    auxiliary.push(
      front.ready
        ? {
            key: "state",
            label: copy("ready"),
            value: copy("readyValue"),
            changeMessage: put("f.changed", () => "%@"),
          }
        : {
            key: "state",
            label: copy("toGo"),
            value: put("f.more", (l) => more(o.goal - front.stamps, l)),
          },
    );
  } else {
    secondary.push({ key: "offer", label: copy("emptyLabel"), value: copy("emptyValue") });
    auxiliary.push({ key: "state", label: copy("howLabel"), value: copy("howValue") });
  }

  const back: object[] = card.standings.map((st, i) => ({
    key: `o${i}`,
    label: put(`b${i}.label`, (l) => pick(st.offer.business.name, l)),
    value: put(`b${i}.value`, (l) => {
      const line = `${pick(st.offer.title, l)} · ${Math.min(st.stamps, st.offer.goal)}/${st.offer.goal} · ${pick(st.offer.reward, l)}`;
      if (!st.rewards) return line;
      return `${line}\n${COPY["rewards"]![l]}: ${st.rewards}`;
    }),
  }));
  back.push(
    { key: "code", label: copy("code"), value: grouped(card.code) },
    { key: "about", label: copy("about"), value: copy("aboutValue") },
  );

  const pass = {
    formatVersion: 1,
    passTypeIdentifier: s.passType,
    teamIdentifier: s.teamId,
    serialNumber: card.code,
    organizationName: "Darb",
    description: copy("description"),
    logoText: copy("logo"),
    backgroundColor: FOREST,
    foregroundColor: IVORY,
    labelColor: MUSTARD,
    sharingProhibited: true,
    ...(s.serviceUrl ? { webServiceURL: s.serviceUrl, authenticationToken: s.authToken } : {}),
    barcodes: [
      {
        format: "PKBarcodeFormatQR",
        message: s.scanUrl,
        messageEncoding: "iso-8859-1",
        altText: grouped(card.code),
      },
    ],
    storeCard: {
      headerFields: header,
      primaryFields: primary,
      secondaryFields: secondary,
      auxiliaryFields: auxiliary,
      backFields: back,
    },
  };

  const files = new Map<string, Buffer>([["pass.json", Buffer.from(JSON.stringify(pass), "utf8")]]);
  for (const lang of LANGS) files.set(`${lang}.lproj/pass.strings`, strings(text[lang]));
  return { files, rows };
}

const FOREST_HEX = "#0B2219";
const IVORY_HEX = "#FBF7EC";
const MUSTARD_HEX = "#FFC330";

/** A round crop of the door: lit in colour for a stamp given, dark and quiet for one still to come. */
const coins = new Map<string, Promise<Buffer>>();
/** Coins are the same for every card: each size is drawn once and kept (a few dozen small PNGs at most). */
function coin(door: Buffer, px: number, lit: boolean): Promise<Buffer> {
  const key = `${px}:${lit ? 1 : 0}`;
  let made = coins.get(key);
  if (!made) {
    made = drawCoin(door, px, lit);
    coins.set(key, made);
  }
  return made;
}

async function drawCoin(door: Buffer, px: number, lit: boolean): Promise<Buffer> {
  const mask = Buffer.from(
    `<svg width="${px}" height="${px}"><circle cx="${px / 2}" cy="${px / 2}" r="${px / 2}" fill="#fff"/></svg>`,
  );
  const art = sharp(door).resize(px, px);
  if (!lit) art.modulate({ brightness: 0.28, saturation: 0.15 });
  return art
    .composite([{ input: mask, blend: "dest-in" }])
    .png()
    .toBuffer();
}

/** Rows of stamps for a goal: one row up to five, then two rows. */
export function layout(goal: number) {
  const rows = goal <= 5 ? 1 : 2;
  const perRow = Math.ceil(goal / rows);
  const gap = perRow > 7 ? 8 : 13;
  const size = Math.min(rows === 1 ? 74 : 57, (375 - 24 - gap * (perRow - 1)) / perRow);
  const rowGap = 12;
  const top = (144 - (rows * size + (rows - 1) * rowGap)) / 2;
  return Array.from({ length: goal }, (_, i) => {
    const row = Math.floor(i / perRow);
    const inRow = row === rows - 1 ? goal - perRow * (rows - 1) : perRow;
    const width = inRow * size + (inRow - 1) * gap;
    return {
      x: (375 - width) / 2 + (i % perRow) * (size + gap),
      y: top + row * (size + rowGap),
      size,
    };
  });
}

const FONTS = {
  he: {
    family: "Heebo Bold",
    file: fileURLToPath(new URL("../../assets/wallet/fonts/Heebo-Bold.ttf", import.meta.url)),
  },
  ar: {
    family: "Cairo Bold",
    file: fileURLToPath(new URL("../../assets/wallet/fonts/Cairo-Bold.ttf", import.meta.url)),
  },
};
let fontsLoaded: Promise<void> | null = null;
/** Both faces registered once, so a Hebrew name in Arabic text (or the reverse) still finds its letters. */
export function loadFonts() {
  fontsLoaded ??= Promise.all(
    Object.values(FONTS).map((f) =>
      sharp({ text: { text: "x", font: `${f.family} 10`, fontfile: f.file, rgba: true } })
        .png()
        .toBuffer(),
    ),
  ).then(() => undefined);
  return fontsLoaded;
}

const escapeMarkup = (t: string) =>
  t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const clip = (t: string, n: number) => (t.length > n ? `${t.slice(0, n - 1).trimEnd()}…` : t);

/** A line of text as an image, no wider than maxWidth pixels. */
async function words(text: string, px: number, color: string, lang: Lang, maxWidth: number) {
  const f = lang === "ar" ? FONTS.ar : FONTS.he;
  const img = await sharp({
    text: {
      text: `<span foreground="${color}">${escapeMarkup(text)}</span>`,
      // the faces were registered once by loadFonts: naming the file again reloads it (seconds a line)
      font: `${f.family} ${px}`,
      rgba: true,
      dpi: 72,
    },
  })
    .png()
    .toBuffer();
  const { width = 0, height = 0 } = await sharp(img).metadata();
  if (width <= maxWidth) return { img, width, height };
  const scaled = await sharp(img)
    .resize({ width: Math.floor(maxWidth) })
    .png()
    .toBuffer();
  return {
    img: scaled,
    width: Math.floor(maxWidth),
    height: Math.round((height * maxWidth) / width),
  };
}

type Layer = { input: Buffer; left: number; top: number };

/** One stamp: the door coin, lit and ringed in gold when given, dark when still to come. */
async function stampAt(
  door: Buffer,
  x: number,
  y: number,
  size: number,
  lit: boolean,
  scale: number,
) {
  const px = Math.round(size * scale);
  const layer: Layer = {
    input: await coin(door, px, lit),
    left: Math.round(x * scale),
    top: Math.round(y * scale),
  };
  const c = { x: (x + size / 2) * scale, y: (y + size / 2) * scale };
  const r = (size / 2 - 0.75) * scale;
  const ring = lit
    ? `<circle cx="${c.x}" cy="${c.y}" r="${r}" fill="none" stroke="${MUSTARD}" stroke-width="${Math.max(1.2, size / 16) * scale}"/>`
    : `<circle cx="${c.x}" cy="${c.y}" r="${r}" fill="none" stroke="rgba(251,247,236,0.16)" stroke-width="${scale}"/>`;
  return { layer, ring };
}

const W = 375;
const H = 144;
const SCALES = [
  ["strip.png", 1],
  ["strip@2x.png", 2],
  ["strip@3x.png", 3],
] as const;

async function flatten(scale: number, layers: Layer[], svg: string) {
  const overlay = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W * scale}" height="${H * scale}">${svg}</svg>`,
  );
  return sharp({
    create: { width: W * scale, height: H * scale, channels: 4, background: FOREST_HEX },
  })
    .composite([...layers, { input: overlay, left: 0, top: 0 }])
    .png()
    .toBuffer();
}

/** One partner, or none yet: big doors across the strip (one lit door when there is no offer at all). */
async function bigDoors(front: LoyaltyStandingDto | null, door: Buffer, scale: number) {
  const goal = front?.offer.goal ?? 0;
  const done = Math.min(front?.stamps ?? 0, goal);
  const spots = front ? layout(goal) : [{ x: (W - 118) / 2, y: (H - 118) / 2, size: 118 }];
  const layers: Layer[] = [];
  let rings = "";
  for (const [i, p] of spots.entries()) {
    const s = await stampAt(door, p.x, p.y, p.size, !front || i < done, scale);
    layers.push(s.layer);
    rings += s.ring;
  }
  return flatten(scale, layers, rings);
}

/**
 * Several partners: a row each, the name and the reward on the reading side, the stamps across from them. Right to
 * left in Hebrew and Arabic, so the first stamp sits nearest the name.
 */
async function partnerRows(rows: LoyaltyStandingDto[], door: Buffer, lang: Lang, scale: number) {
  const rtl = lang !== "en";
  const n = rows.length;
  const padX = 16;
  const padY = 6;
  const rowH = (H - padY * 2) / n;
  const nameW = 148;
  const dotsW = W - padX * 2 - nameW - 12;
  const twoLines = rowH >= 40;
  const namePx = n <= 2 ? 18 : n === 3 ? 15 : 14;
  const layers: Layer[] = [];
  let svg = "";
  for (const [r, st] of rows.entries()) {
    const top = padY + r * rowH;
    if (r > 0)
      svg += `<rect x="${padX * scale}" y="${top * scale}" width="${(W - padX * 2) * scale}" height="${Math.max(1, scale * 0.6)}" fill="rgba(251,247,236,0.10)"/>`;
    const o = st.offer;
    const name = await words(
      clip(pick(o.business.name, lang), 20),
      namePx * scale,
      IVORY_HEX,
      lang,
      nameW * scale,
    );
    const sub = twoLines
      ? await words(
          clip(
            st.ready ? `${COPY["ready"]![lang]} · ${pick(o.reward, lang)}` : pick(o.reward, lang),
            28,
          ),
          (n <= 2 ? 12 : 11) * scale,
          MUSTARD_HEX,
          lang,
          nameW * scale,
        )
      : null;
    const lineGap = sub ? Math.round(2 * scale) : 0;
    const block = name.height + lineGap + (sub ? sub.height : 0);
    let y = Math.round((top + rowH / 2) * scale - block / 2);
    const side = (w: number) => Math.round(rtl ? (W - padX) * scale - w : padX * scale);
    layers.push({ input: name.img, left: side(name.width), top: y });
    y += name.height + lineGap;
    if (sub) layers.push({ input: sub.img, left: side(sub.width), top: y });

    const goal = o.goal;
    const done = Math.min(st.stamps, goal);
    const gap = 4;
    const size = Math.min(rowH * 0.62, 26, (dotsW - gap * (goal - 1)) / goal);
    const width = goal * size + (goal - 1) * gap;
    // the stamps sit across from the name, the first one nearest it
    const start = rtl ? padX + (dotsW - width) : W - padX - dotsW;
    const cy = top + rowH / 2 - size / 2;
    for (let i = 0; i < goal; i++) {
      const slot = rtl ? goal - 1 - i : i;
      const x = start + slot * (size + gap);
      const lit = i < done;
      if (size >= 14) {
        const s = await stampAt(door, x, cy, size, lit, scale);
        layers.push(s.layer);
        svg += s.ring;
      } else {
        const c = { x: (x + size / 2) * scale, y: (cy + size / 2) * scale };
        svg += lit
          ? `<circle cx="${c.x}" cy="${c.y}" r="${(size / 2) * scale}" fill="${MUSTARD}"/>`
          : `<circle cx="${c.x}" cy="${c.y}" r="${(size / 2 - 0.5) * scale}" fill="none" stroke="rgba(251,247,236,0.25)" stroke-width="${scale}"/>`;
      }
    }
  }
  return flatten(scale, layers, svg);
}

/**
 * The strip across the front of the card. One partner: its stamps as big doors that light up in gold. Several:
 * a row per partner (up to four), each with its own doors. The rows carry names, so they are drawn per language.
 * Drawn at 1x, 2x and 3x (375 by 144 points).
 */
export async function strip(
  standings: LoyaltyStandingDto[],
  door: Buffer,
): Promise<Map<string, Buffer>> {
  const rows = ordered(standings).slice(0, FRONT_ROWS);
  const out = new Map<string, Buffer>();
  if (rows.length <= 1) {
    for (const [name, scale] of SCALES) out.set(name, await bigDoors(rows[0] ?? null, door, scale));
    return out;
  }
  await loadFonts();
  for (const lang of LANGS)
    for (const [name, scale] of SCALES) {
      const png = await partnerRows(rows, door, lang, scale);
      // per language only: Wallet prefers a shared strip over a localized one when both exist
      out.set(`${lang}.lproj/${name}`, png);
    }
  return out;
}
