#!/usr/bin/env node
// Bring the website's own words into the iPhone app, so the two say the same thing.
//
//   node scripts/sync-copy.mjs            refresh the copy taken from the website
//   node scripts/sync-copy.mjs --check    also fail when the app uses a phrase the catalog does not have
//
// What it reads, all three languages of each:
//   packages/i18n/src/messages/{he,ar,en}.ts      the shared phrases          -> web.messages.*
//   apps/web/src/content/contact.ts               the contact form            -> web.contact.*
//   apps/web/src/content/join.ts                  the join form               -> web.join.*
//   apps/web/src/content/landing.ts               what Darb says about itself -> web.landing.*
//   apps/web/src/content/near.ts                  the location request        -> web.near.*
//   apps/web/src/content/legal.ts                 terms and privacy           -> Darb/Resources/Data/legal.json
//
// What it writes:
//   Darb/Resources/Localizable.xcstrings   Every key that starts with "web." is replaced; every other key is
//                                          the app's own copy and is left exactly as it is.
//   Darb/Resources/Data/legal.json         The terms and the privacy policy, rendered natively by the app.
//
// A placeholder such as {place} becomes %@ (or %1$@, %2$@ when a phrase has more than one), in the order the
// Hebrew has them, so the app fills them the same way in every language.
import { registerHooks } from "node:module";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const ios = join(here, "..");
const repo = join(ios, "..", "..");
const LANGS = ["he", "ar", "en"];

// the website's files import each other without an extension
registerHooks({
  resolve(spec, ctx, next) {
    if (spec.startsWith(".") && !/\.[a-z]+$/.test(spec)) {
      const url = new URL(spec + ".ts", ctx.parentURL);
      if (existsSync(fileURLToPath(url))) return { url: url.href, shortCircuit: true };
    }
    return next(spec, ctx);
  },
});
const load = async (path) => import(pathToFileURL(join(repo, path)).href);

const flat = (value, prefix = "") =>
  Object.entries(value).flatMap(([k, v]) =>
    v && typeof v === "object" ? flat(v, `${prefix}${k}.`) : typeof v === "string" ? [[prefix + k, v]] : [],
  );

/** {place} and {count} become format arguments, numbered by where the Hebrew has them. */
function placeholders(texts) {
  const names = [...texts.he.matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
  if (names.length === 0) return texts;
  const out = {};
  for (const lang of LANGS) {
    out[lang] = texts[lang].replace(/%/g, "%%").replace(/\{(\w+)\}/g, (_, name) => {
      const i = names.indexOf(name);
      return i < 0 ? "" : names.length === 1 ? "%@" : `%${i + 1}$@`;
    });
  }
  return out;
}

/** A dash between words reads as a pause the app's copy does not use; the legal pages keep theirs. */
const noDash = (text) => text.replace(/\s+[–—-]\s+/g, ", ").replace(/[–—]/g, "-");

/** The app's copy never names a language or a faith, and never says these words; a website phrase that does is left out. */
const OFF_COPY =
  /חלאל|(?<![א-ת])כשר(?![א-ת])|עברית|ערבית|אנגלית|حلال|كوشير|العربية|العبرية|الإنجليزية|بالعربي|بالعبري|halal|kosher|hebrew|arabic|english/i;

const web = {};
function take(prefix, byLang, skip = () => false) {
  const tables = Object.fromEntries(LANGS.map((l) => [l, Object.fromEntries(flat(byLang[l]))]));
  for (const key of Object.keys(tables.he)) {
    if (skip(key, tables.he[key])) continue;
    const texts = Object.fromEntries(LANGS.map((l) => [l, noDash(tables[l][key] ?? tables.he[key])]));
    if (LANGS.some((l) => OFF_COPY.test(texts[l]))) continue;
    web[`${prefix}.${key}`] = placeholders(texts);
  }
}

const messages = {};
for (const lang of LANGS) {
  const m = await load(`packages/i18n/src/messages/${lang}.ts`);
  messages[lang] = Object.values(m)[0];
}
take("web.messages", messages);
take("web.contact", (await load("apps/web/src/content/contact.ts")).contact);
take("web.near", (await load("apps/web/src/content/near.ts")).near);
take("web.join", (await load("apps/web/src/content/join.ts")).join, (key) => key.startsWith("preview.") || key.startsWith("map.gestures"));
take("web.landing", (await load("apps/web/src/content/landing.ts")).landing, (_, value) => value.startsWith("http"));

// the catalog: replace what came from the website, keep the app's own
const catalogPath = join(ios, "Darb", "Resources", "Localizable.xcstrings");
const catalog = existsSync(catalogPath)
  ? JSON.parse(readFileSync(catalogPath, "utf8"))
  : { sourceLanguage: "he", version: "1.0", strings: {} };
for (const key of Object.keys(catalog.strings)) if (key.startsWith("web.")) delete catalog.strings[key];
for (const [key, texts] of Object.entries(web)) {
  catalog.strings[key] = {
    extractionState: "manual",
    localizations: Object.fromEntries(LANGS.map((l) => [l, { stringUnit: { state: "translated", value: texts[l] } }])),
  };
}
catalog.strings = Object.fromEntries(Object.entries(catalog.strings).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + "\n");

// terms and privacy
const legal = await load("apps/web/src/content/legal.ts");
const docs = {};
for (const kind of ["terms", "privacy"]) {
  docs[kind] = Object.fromEntries(
    LANGS.map((l) => {
      const d = legal.legal[kind][l];
      return [
        l,
        {
          title: d.title,
          lead: d.lead,
          sections: d.sections.map((s) => ({
            id: s.id,
            title: s.title,
            blocks: s.blocks.map((b) => (typeof b === "string" ? { text: b } : { list: [...b.list] })),
          })),
        },
      ];
    }),
  );
}
writeFileSync(
  join(ios, "Darb", "Resources", "Data", "legal.json"),
  JSON.stringify({ updated: legal.LEGAL_UPDATED, email: legal.LEGAL_CONTACT.email, chrome: legal.legalChrome, docs }),
);

// every phrase the app asks for must be in the catalog, in all three languages
function swiftFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? swiftFiles(join(dir, e.name)) : e.name.endsWith(".swift") ? [join(dir, e.name)] : [],
  );
}
const used = new Set();
for (const file of [...swiftFiles(join(ios, "Darb")), ...swiftFiles(join(ios, "DarbWidget"))]) {
  const source = readFileSync(file, "utf8");
  for (const m of source.matchAll(/\bL\("((?:[^"\\]|\\.)*)"/g)) used.add(m[1].replace(/\\"/g, '"'));
}
const missing = [...used].filter((key) => {
  // a key that is finished at run time ("web.contact.form.topics." + topic) is checked by the tests instead
  if ((key.startsWith("web.") && key.endsWith(".")) || key.includes("\\(")) return false;
  const entry = catalog.strings[key];
  return !entry || LANGS.some((l) => !entry.localizations?.[l]?.stringUnit?.value);
});
const own = Object.keys(catalog.strings).filter((k) => !k.startsWith("web."));
console.log(`${Object.keys(web).length} phrases from the website, ${own.length} of the app's own, ${used.size} used in code.`);
if (missing.length) {
  console.log(`${missing.length} used in code but not in the catalog in all three languages:`);
  for (const key of missing) console.log("  " + key);
  if (process.argv.includes("--check")) process.exit(1);
}
