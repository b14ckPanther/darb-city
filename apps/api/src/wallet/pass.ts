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

/** The card shown on the front: a reward ready to collect, else the latest stamped, else the newest offer. */
export function lead(standings: LoyaltyStandingDto[]): LoyaltyStandingDto | null {
  const ready = standings.find((s) => s.ready);
  if (ready) return ready;
  const stamped = standings
    .filter((s) => s.lastStampAt)
    .sort((a, b) => b.lastStampAt!.localeCompare(a.lastStampAt!));
  return stamped[0] ?? standings[standings.length - 1] ?? null;
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
  const front = lead(card.standings);
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
  if (front) {
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
    if (card.standings.length > 1)
      auxiliary.push({ key: "offers", label: copy("offers"), value: card.standings.length });
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
  return { files, front };
}

const FOREST_HEX = "#0B2219";

/** A round crop of the door: lit in colour for a stamp given, dark and quiet for one still to come. */
async function coin(door: Buffer, px: number, lit: boolean): Promise<Buffer> {
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

/**
 * The strip across the front of the card: the stamps themselves. Each is a coin with the Darb door, which lights
 * up in gold when the counter stamps it; the rest wait dark. A card with no offer yet shows one door, lit.
 * Drawn at 1x, 2x and 3x (375 by 144 points).
 */
export async function strip(
  front: LoyaltyStandingDto | null,
  door: Buffer,
): Promise<Map<string, Buffer>> {
  const W = 375;
  const H = 144;
  const goal = front?.offer.goal ?? 0;
  const done = Math.min(front?.stamps ?? 0, goal);
  const spots = front ? layout(goal) : [{ x: (W - 118) / 2, y: (H - 118) / 2, size: 118 }];
  const out = new Map<string, Buffer>();
  for (const [name, scale] of [
    ["strip.png", 1],
    ["strip@2x.png", 2],
    ["strip@3x.png", 3],
  ] as const) {
    const layers: { input: Buffer; left: number; top: number }[] = [];
    let rings = "";
    for (const [i, p] of spots.entries()) {
      const lit = !front || i < done;
      const px = Math.round(p.size * scale);
      layers.push({
        input: await coin(door, px, lit),
        left: Math.round(p.x * scale),
        top: Math.round(p.y * scale),
      });
      const c = { x: (p.x + p.size / 2) * scale, y: (p.y + p.size / 2) * scale };
      const r = (p.size / 2 - 1) * scale;
      rings += lit
        ? `<circle cx="${c.x}" cy="${c.y}" r="${r}" fill="none" stroke="${MUSTARD}" stroke-width="${1.8 * scale}"/>`
        : `<circle cx="${c.x}" cy="${c.y}" r="${r}" fill="none" stroke="rgba(251,247,236,0.16)" stroke-width="${1.5 * scale}"/>`;
    }
    const overlay = Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${W * scale}" height="${H * scale}">${rings}</svg>`,
    );
    out.set(
      name,
      await sharp({
        create: { width: W * scale, height: H * scale, channels: 4, background: FOREST_HEX },
      })
        .composite([...layers, { input: overlay, left: 0, top: 0 }])
        .png()
        .toBuffer(),
    );
  }
  return out;
}
