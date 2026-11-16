/*
 * The road to Darb. Every stage, plan and step from day one to the real launch.
 * `done: true` on a step marks what was already shipped when this map was drawn (2026-10-17);
 * everything you tick after that lives in this browser (and in your exported backups).
 */
window.DARB_ROAD = {
  dayOne: "2026-10-12",
  drawn: "2026-10-17",
  updated: "2026-11-16",
  launchTarget: "2027-03-01",

  waiting: [
    { id: "w-password", text: "Change the admin password (it was shared in chat)" },
    { id: "w-technion", text: "Technion: move the old Nesher row to Haifa as a university, or suspend it" },
    { id: "w-clerk-pw", text: "Clerk: turn passwords off (email code only), or set the minimum to 8" },
    { id: "w-helpers-invite", text: "Send darb.co.il/ar/helpers to the first friends and approve them" },
    { id: "w-staging", text: "Decide: staging real-only too, or keep its example businesses" },
    { id: "w-lookup", text: "Try darb.co.il/join once with a real business, so the smart lookup gets its first real run" },
    { id: "w-ar-card", text: "Confirm the card's Arabic: فاتح للساعة, بيفتح بكرا الساعة, مسكّر اليوم, كيف توصلهم, عالسوشيال ميديا" },
    { id: "w-religion", text: "Religion category: rename to a neutral name and move butchers and modest clothing?" },
    { id: "w-kids", text: "Kids in Arabic: أطفال وبيبي or أطفال?" },
    { id: "w-words", text: "Confirm Arabic words: أقفالجية, بياطرة, عيادات أم وطفل" },
    { id: "w-legal", text: "Legal facts: operator name and spelling, hosting regions, response times wording" },
    { id: "w-turan", text: "Where exactly is Paz Bik'at Tur'an? (the government pin repeats Mitzpe Turan's)" },
  ],

  stages: [
    {
      id: "s0",
      name: "Foundations",
      tagline: "The ground the whole city stands on.",
      plans: [
        { id: "p1", n: "1", title: "Foundation and data", line: "Monorepo, database, every place, sector and kind in three languages.", size: "L", steps: [
          { t: "pnpm monorepo: web, API, contracts, core, seed", done: true },
          { t: "Postgres with PostGIS and pgvector, Prisma migrations", done: true },
          { t: "1,138 places, 18 sectors, 205 kinds, in Hebrew, Arabic and English", done: true },
          { t: "Seed loader that never overwrites admin edits", done: true },
        ]},
        { id: "p2a", n: "2a", title: "The city on the web", line: "Country, town, sector, kind and business pages, RTL first.", size: "L", steps: [
          { t: "Level pages from Israel down to a business", done: true },
          { t: "Hebrew and Arabic right to left, English left to right", done: true },
          { t: "Cached pages that refresh when data changes", done: true },
        ]},
        { id: "p2b", n: "2b", title: "The map", line: "A self-hosted map in Darb's own style.", size: "L", steps: [
          { t: "MapLibre with self-hosted tiles on Cloudflare R2", done: true },
          { t: "Count bubbles that zoom in, empty places hidden", done: true },
          { t: "Camera that follows the city's levels", done: true },
        ]},
        { id: "p3", n: "3", title: "Smart search", line: "Write it like you'd tell a friend. Darb understands.", size: "L", ai: true, steps: [
          { t: "Instant search of places and kinds, offline-capable", done: true },
          { t: "Intent model with recorded fallbacks", done: true },
          { t: "Embeddings and ranking, quality set in CI", done: true },
        ]},
        { id: "p4", n: "4", title: "Admin and launch", line: "The dashboard, the cloud, and darb.co.il live.", size: "L", steps: [
          { t: "Admin with Clerk sign-in", done: true },
          { t: "Railway API and Redis, Neon Postgres, Vercel web", done: true },
          { t: "darb.co.il, admin, staging and API domains live", done: true },
        ]},
      ],
    },
    {
      id: "s1",
      name: "The new front door",
      tagline: "The first impression every owner deserves.",
      plans: [
        { id: "r1", n: "R1", title: "Landing, showroom, pricing", line: "The blueprint hero, the gold road, live client apps.", size: "L", steps: [
          { t: "Landing with the blueprint mark and the road drawn on scroll", done: true },
          { t: "Showroom: one section per project, live viewer, laptop sideways on phones", done: true },
          { t: "Pricing fully editable in admin, plain words, free plan on top", done: true },
          { t: "Legal pages in three languages", done: true },
          { t: "Phone hero: copy first, big mark above the search bar", done: true },
        ]},
        { id: "r2", n: "R2", title: "Owners can come in", line: "Contact, join, and the admin's approval queue.", size: "L", ai: true, steps: [
          { t: "Contact form into the admin Messages inbox", done: true },
          { t: "Smart /join: name, link or GPS fills the card", done: true },
          { t: "Photo uploads to media.darb.co.il", done: true },
          { t: "Join requests queue with approve and reject", done: true },
          { t: "Draggable pin in admin, no more typing coordinates", done: true },
        ]},
        { id: "r3", n: "R3", title: "Cards worth opening", line: "Every business, in its own colour, with icons not labels.", size: "M", steps: [
          { t: "Designed cards: accent band, today dial, round icon buttons", done: true },
          { t: "Waze on every card, home businesses keep their street private", done: true },
          { t: "Fuel station screen: pump faces and a service grid", done: true },
        ]},
        { id: "r4", n: "R4", title: "Real data only", line: "No more examples. Only businesses that exist.", size: "M", steps: [
          { t: "Production shows only real businesses", done: true },
          { t: "87 Paz stations in the north with official phones and services", done: true },
          { t: "Production seed approved and live", done: true },
          { t: "Stations found by their services: EV charging, car wash", done: true },
          { t: "Staging real-only too", done: false, you: true },
        ]},
        { id: "r5", n: "R5", title: "Near me, for real", line: "Your exact spot, the businesses around you, live distances.", size: "M", steps: [
          { t: "Live distance on every row, updating as you move", done: true },
          { t: "Precise near-me page with a you-are-here map", done: true },
          { t: "Equal-height rows, distance as a gold chip", done: true },
          { t: "Pages lighter: business page 40.7 KB to 30.6 KB", done: true },
          { t: "Shipped to production", done: true },
          { t: "Paz cards credit the YellowShifts app Darb built", done: true },
        ]},
        { id: "r6", n: "R6", title: "Search that reads every card", line: "\"Gluten-free shawarma\" finds the dish inside Caramel.", size: "L", ai: true, steps: [
          { t: "Offerings: every card's dishes, services and products searchable", done: true },
          { t: "Intent names the exact thing wanted, and what is a must", done: true },
          { t: "Strict facts: gluten-free only shows gluten-free kitchens", done: true },
          { t: "Never a dead end: the honest closest option with its distance", done: true },
          { t: "The matched item highlighted on the business's screen", done: true },
          { t: "Merged and reindexed on production", done: true },
          { t: "Record the live model on real queries", done: false },
        ]},
        { id: "r7", n: "R7", title: "The daylight map", line: "Sunlit land, a teal sea, gold roads. Only Darb's land comes alive.", size: "M", steps: [
          { t: "Israel only: foreign towns and roads hidden", done: true },
          { t: "Daylight atlas: ivory land, sage parks, teal sea, gold highways", done: true },
          { t: "Outside Darb's land: plain land, whole sea, nothing built", done: true },
          { t: "The light map framed like a lit window", done: true },
          { t: "Shipped to production", done: true },
        ]},
        { id: "r8", n: "R8", title: "A map that shows only what you want", line: "No wall of numbers: only the pins you are looking for.", size: "M", steps: [
          { t: "Calm map while browsing, the town highlighted", done: true },
          { t: "Category preview: only that category's pins", done: true },
          { t: "Numbered pins matching the list, a bottom card on phones", done: true },
          { t: "Category list: one per row, same size, sorted by count", done: true },
        ]},
        { id: "r9", n: "R9", title: "Darb as an app", line: "Short name, two icon sets, shortcuts, a native feel.", size: "M", steps: [
          { t: "Short name in every language", done: true },
          { t: "Light and dark icon sets, tabs follow the phone", done: true },
          { t: "Manifest per language with shortcuts and screenshots", done: true },
          { t: "Native feel when installed: safe areas, no white flash", done: true },
        ]},
        { id: "r10", n: "R10", title: "Small fixes", line: "What the owner noticed, fixed.", size: "S", steps: [
          { t: "Admin shows only real businesses; examples deleted from production", done: true },
          { t: "Sitemaps split so the warm job passes again", done: true },
          { t: "Names pill above the hero removed", done: true },
          { t: "Footer links the new LinkedIn address", done: true },
          { t: "Every card screen designed for its kind, no generic templates", done: true },
          { t: "Darb-built apps previewed on their card; a quiet owner line on the rest", done: true },
          { t: "Business card opens full on phones", done: true },
          { t: "A README that explains Darb, with the team", done: true },
          { t: "Admin: find the place by address or a pasted map link", done: true },
          { t: "Google reviews button on cards (a link, nothing copied)", done: true },
          { t: "Universities and colleges as their own kind", done: true },
          { t: "Smart search that answers: time to think, typos, dialects, precision", done: true },
          { t: "Admin redesigned: sidebar, overview, real lists, sectioned editor", done: true },
          { t: "Edit any business right from its public card; LinkedIn and more links", done: true },
          { t: "Admin sidebar highlights the screen you are on", done: true },
        ]},
        { id: "r11", n: "R11", title: "Darb helpers", line: "Friends add the businesses of their towns; nothing goes public without you.", size: "L", steps: [
          { t: "Open sign up, admin approves (Waiting, Active, Paused)", done: true },
          { t: "Helper app at /helpers with its own icon, in three languages", done: true },
          { t: "Quick add in three taps: photo, check, send; works offline", done: true },
          { t: "Long press shortcuts, share a Maps link or photo into the app", done: true },
          { t: "My additions: waiting, live, not added with the reason", done: true },
          { t: "Public credit toggle: \"Added to Darb by\" on live cards", done: true },
          { t: "Daily limits 150 / 500 / no limit per helper", done: true },
          { t: "Approve all from one helper; unusual pace alert on Overview", done: true },
          { t: "Send stamp, milestones, went live note, counting numbers", done: true },
        ]},
        { id: "r12", n: "R12", title: "Darb admin as an app", line: "The admin on your home screen.", size: "S", steps: [
          { t: "Own icon with a shield badge, opens full screen", done: true },
          { t: "Shortcuts: add from the street, join requests, helpers", done: true },
          { t: "Waiting count on the app icon", done: true },
          { t: "Gold check when approving", done: true },
        ]},
        { id: "r13", n: "R13", title: "Darb's own sign in", line: "No more dry Clerk forms.", size: "M", steps: [
          { t: "One question at a time, Darb look, light and dark", done: true },
          { t: "Six digit code fills left to right, paste and autofill", done: true },
          { t: "Same screens for helpers and admin (admin sign in only)", done: true },
          { t: "Lands straight in the app after signing in", done: true },
        ]},
        { id: "r14", n: "R14", title: "Launch screen", line: "Walk through the lit door into the app.", size: "S", steps: [
          { t: "iPhone launch images, light and dark", done: true },
          { t: "Doorway reveal with each app's own beat, tap to skip", done: true },
          { t: "Slowed to 2 seconds so it can be seen", done: true },
        ]},
      ],
    },
    {
      id: "sday",
      name: "Darb by day",
      tagline: "Warm, open, alive. Never depressing.",
      plans: [
        { id: "d1", n: "D1", title: "The whole site in daylight", line: "Ivory and sand, white cards, forest text, gold highlights.", size: "M", steps: [
          { t: "Light colour tokens for every page", done: true },
          { t: "Cards, lists and sheets in daylight", done: true },
          { t: "Admin in daylight too", done: true },
          { t: "Every page checked for contrast", done: true },
        ]},
        { id: "d2", n: "D2", title: "Night mode, automatic", line: "Today's dark look, for the phone's dark setting and late evenings.", size: "S", steps: [
          { t: "Follows the phone's dark setting", done: true },
          { t: "A toggle in the menu, remembered", done: true },
        ]},
        { id: "d3", n: "D3", title: "Night to day on the landing", line: "The hero opens dark, the gold road leads into daylight.", size: "S", steps: [
          { t: "Hero keeps its night drama", done: true },
          { t: "Scroll warms the page into day", done: true },
        ]},
        { id: "d4", n: "D4", title: "Photos everywhere", line: "Real faces, real food, real streets.", size: "M", steps: [
          { t: "Owners' photos on cards and rows" },
          { t: "Real towns on the landing" },
        ]},
      ],
    },
    {
      id: "s2",
      name: "Solid ground",
      tagline: "Nothing breaks. Nothing waits.",
      plans: [
        { id: "p5", n: "5", title: "Polish and hardening", line: "The 45 small things parked in reviews, cleared.", size: "L", steps: [
          { t: "Seed writes inside the transaction, never over an admin edit" },
          { t: "Admin lists page by cursor, not offset" },
          { t: "Search cache, retention batches, Redis round trips" },
          { t: "Localized admin error messages" },
          { t: "Trim shared message tables out of browser bundles", done: true },
          { t: "Remove the retired plaza code" },
          { t: "Pin CI actions to commits" },
          { t: "Checks run in parallel: 11 minutes, not 21", done: true },
          { t: "Admin lists work in Safari: clicking search no longer opens a business", done: true },
        ]},
        { id: "p28", n: "28", title: "Monitoring and alerts", line: "You hear about a problem before a customer does.", size: "M", steps: [
          { t: "Error tracking on web and API" },
          { t: "Uptime checks for darb.co.il, api and media" },
          { t: "Cost alerts for AI and maps" },
          { t: "Nightly backups with a monthly restore test" },
          { t: "Bot protection on, scraper proxy networks blocked", done: true },
        ]},
        { id: "p35", n: "35", title: "Speed pass", line: "Under a second on a mid-range phone on 4G.", size: "M", steps: [
          { t: "Measure every page on a real Android over 4G" },
          { t: "Images and fonts trimmed, maps loaded only when seen" },
          { t: "Budgets enforced for every route in CI" },
        ]},
      ],
    },
    {
      id: "s3",
      name: "A real city",
      tagline: "Every town, full of businesses that actually exist.",
      plans: [
        { id: "p6", n: "6", title: "Real data, more of it", line: "Official open data, imported with care.", size: "L", steps: [
          { t: "Other fuel chains: Delek, Sonol, Dor Alon, Ten, Yellow stores", done: true },
          { t: "Pharmacies, post offices, banks, clinics", done: true },
          { t: "Schools, kindergartens, municipal services", done: true },
          { t: "Every import records its source and licence", done: true },
          { t: "Copy decisions: religion category, Arabic words", done: true },
          { t: "Food: 1,348 restaurants, cafes, bakeries, sweets", done: true },
          { t: "Garages and testing stations pinned by address (647)", done: true },
          { t: "Every other category with a per-kind coverage audit", done: true },
          { t: "13,256 real businesses live in the north", done: true },
          { t: "Fill the thin kinds and Arab towns (owners, field collection)" },
          { t: "Add from the street: photo of the sign, GPS, review before publishing", done: true },
          { t: "Remaining formal Arabic labels in local dialect" },
        ]},
        { id: "p20", n: "20", title: "Claim your business", line: "Imported listings get their real owners.", size: "M", steps: [
          { t: "Claim by SMS code to the listed phone" },
          { t: "Claim by documents, reviewed in admin" },
          { t: "Claimed badge and owner contact on the card" },
        ]},
        { id: "p30", n: "30", title: "Data freshness", line: "A map that never goes stale.", size: "M", steps: [
          { t: "Scheduled re-import of open data" },
          { t: "Flag closed businesses from reports and imports" },
          { t: "Ask owners to confirm their hours every few months" },
        ]},
        { id: "p52", n: "52", title: "Smart data cleaner", line: "Duplicates, wrong pins and missing phones, found for you.", size: "M", ai: true, steps: [
          { t: "Find duplicates and pins in the wrong place" },
          { t: "Suggest phones and hours from public sources" },
          { t: "One-click fixes in admin" },
        ]},
      ],
    },
    {
      id: "s4",
      name: "Owners at home",
      tagline: "A studio every business owner deserves.",
      plans: [
        { id: "p7", n: "7", title: "Owner studio", line: "Owners sign in and keep their card alive.", size: "L", steps: [
          { t: "Owner sign-in by phone" },
          { t: "Edit hours, photos, links, colours" },
          { t: "Changes go to you for approval" },
          { t: "Preview the card exactly as people see it" },
        ]},
        { id: "p21", n: "21", title: "Owner insights", line: "Views, calls, Waze taps, and who searched but missed them.", size: "M", steps: [
          { t: "Count views, calls, WhatsApp, Waze, shares" },
          { t: "Monthly summary in plain words" },
          { t: "Searches near them that found nothing" },
        ]},
        { id: "p45", n: "45", title: "Smart card writer", line: "Descriptions and menus in every language, in Darb's voice.", size: "S", ai: true, steps: [
          { t: "Write the description from what the owner gives" },
          { t: "Translate with the copy rules: dialect Arabic, no dashes" },
          { t: "Owner approves before it goes live" },
        ]},
        { id: "p46", n: "46", title: "Menu from a photo", line: "Photograph the board, get a real menu.", size: "M", ai: true, steps: [
          { t: "Read a menu or price list photo into items" },
          { t: "Owner checks and fixes before publishing" },
        ]},
        { id: "p22", n: "22", title: "WhatsApp updates", line: "Owners update their card by sending a message.", size: "M", ai: true, steps: [
          { t: "WhatsApp Business number for Darb" },
          { t: "\"Closed tomorrow\", \"new dish\": understood and applied" },
          { t: "Every change confirmed back to the owner" },
        ]},
        { id: "p23", n: "23", title: "Chains and branches", line: "One owner, many branches, one change.", size: "M", steps: [
          { t: "Group branches under a chain" },
          { t: "Edit once, apply to all or some" },
        ]},
        { id: "p24", n: "24", title: "Badges and trust", line: "Checked by Darb, so people can rely on them.", size: "S", steps: [
          { t: "Verified by Darb, family business, accessible" },
          { t: "Each badge checked and dated in admin" },
        ]},
        { id: "p49", n: "49", title: "Post creator", line: "A deal becomes an Instagram post in the card's style.", size: "S", ai: true, steps: [
          { t: "Post and story images from a deal or dish" },
          { t: "Captions in each language" },
        ]},
        { id: "p50", n: "50", title: "Photo enhancer", line: "Their photos, better. Never fake.", size: "S", ai: true, steps: [
          { t: "Straighten, light and crop for the card" },
          { t: "Original always kept" },
        ]},
      ],
    },
    {
      id: "s5",
      name: "Be found",
      tagline: "When anyone looks, Darb is the answer.",
      plans: [
        { id: "p8", n: "8", title: "Growth and SEO", line: "Google understands every business on Darb.", size: "M", steps: [
          { t: "Structured business data on every card" },
          { t: "Per-place sitemaps and Search Console", done: true },
          { t: "Share images for every page" },
          { t: "A clean Google result: right words, the brand once in each title", done: true },
          { t: "AI training crawlers kept out, AI search crawlers welcome", done: true },
        ]},
        { id: "p32", n: "32", title: "Sharing and QR", line: "Every shop window points to Darb.", size: "S", steps: [
          { t: "Beautiful share card per business" },
          { t: "QR stickers owners can print" },
          { t: "Instagram story templates" },
        ]},
        { id: "p31", n: "31", title: "More languages", line: "Russian, Amharic and more, in any language.", size: "M", steps: [
          { t: "Add a fourth language end to end" },
          { t: "Search understands it too" },
        ]},
        { id: "p33", n: "33", title: "Partnerships", line: "Darb inside municipality and council sites.", size: "M", steps: [
          { t: "Embeddable Darb widget" },
          { t: "Public API for partners" },
        ]},
        { id: "p34", n: "34", title: "Marketing extras", line: "The stories that sell the next client.", size: "S", steps: [
          { t: "A case study per client" },
          { t: "A blog in local voice" },
          { t: "Press kit" },
        ]},
      ],
    },
    {
      id: "s6",
      name: "Smart Darb",
      tagline: "It knows what you mean, and it never makes things up.",
      plans: [
        { id: "p41", n: "41", title: "Answers from the card", line: "\"Do you have parking?\" Answered from what the owner published.", size: "S", ai: true, steps: [
          { t: "Ask any card a question" },
          { t: "Says plainly when it does not know" },
        ]},
        { id: "p39", n: "39", title: "Ask Darb", line: "A chat that answers with real cards.", size: "L", ai: true, steps: [
          { t: "Understands needs, places, times, diets" },
          { t: "Answers only with real businesses" },
          { t: "Asks one follow-up when needed" },
          { t: "Daily cost cap with a cheaper fallback" },
        ]},
        { id: "p40", n: "40", title: "Day planner", line: "\"Saturday in Nazareth with kids\": a route of real places.", size: "M", ai: true, steps: [
          { t: "Plan a few stops with times" },
          { t: "Waze links between them" },
        ]},
        { id: "p42", n: "42", title: "Personal suggestions", line: "People near you also liked, kept on your device.", size: "M", ai: true, steps: [
          { t: "Suggestions from favourites, on the device" },
          { t: "Never sold, never shared" },
        ]},
        { id: "p43", n: "43", title: "Photo and voice search", line: "Point the camera, or just say it.", size: "M", ai: true, steps: [
          { t: "Photo of a dish, product or sign" },
          { t: "Voice in any language or dialect" },
        ]},
        { id: "p51", n: "51", title: "Auto review of join requests", line: "Duplicates and excluded businesses caught before you look.", size: "S", ai: true, steps: [
          { t: "Check category, duplicates and exclusions" },
          { t: "Approve with one click" },
        ]},
        { id: "p53", n: "53", title: "Lead finder", line: "Who would love a Darb app, with a message drafted.", size: "S", ai: true, steps: [
          { t: "Find strong demand with no site" },
          { t: "Draft a personal message" },
        ]},
        { id: "p54", n: "54", title: "Search gaps report", line: "What people wanted and did not find, by town.", size: "S", ai: true, steps: [
          { t: "Weekly gaps by town and kind" },
          { t: "Turn a gap into a lead" },
        ]},
        { id: "p55", n: "55", title: "Copy guard", line: "Every text checked against your rules.", size: "S", ai: true, steps: [
          { t: "No halal, no dashes, dialect Arabic, no language names" },
          { t: "Runs in CI and in admin" },
        ]},
      ],
    },
    {
      id: "s7",
      name: "Trust and community",
      tagline: "People come back because Darb remembers them.",
      plans: [
        { id: "p13", n: "13", title: "Favourites and lists", line: "My places, and lists worth sharing.", size: "M", steps: [
          { t: "Save businesses on the device" },
          { t: "Shareable lists" },
        ]},
        { id: "p17", n: "17", title: "Visitor accounts", line: "Optional sign-in, so favourites travel.", size: "M", steps: [
          { t: "Phone or Google sign-in" },
          { t: "Sync favourites and reviews" },
        ]},
        { id: "p14", n: "14", title: "Reviews and ratings", line: "Real, with photos, never faked.", size: "L", steps: [
          { t: "Reviews with photos" },
          { t: "Owner replies" },
          { t: "Moderation queue" },
        ]},
        { id: "p44", n: "44", title: "Review summaries", line: "What people love and what to know, in your language.", size: "S", ai: true, steps: [
          { t: "Summaries from real reviews only" },
        ]},
        { id: "p15", n: "15", title: "Deals and events", line: "What's on near me, with an end date.", size: "M", steps: [
          { t: "Owners post deals and events" },
          { t: "What's on near me page" },
        ]},
        { id: "p16", n: "16", title: "Notifications", line: "Only what you asked for.", size: "M", steps: [
          { t: "New deal from a saved place" },
          { t: "New business in your town" },
        ]},
        { id: "p26", n: "26", title: "Moderation and safety", line: "Darb stays clean, automatically.", size: "M", steps: [
          { t: "Report a listing" },
          { t: "Keep bars, pork and gambling out automatically" },
          { t: "Blocked words list" },
        ]},
      ],
    },
    {
      id: "s8",
      name: "The business engine",
      tagline: "Darb pays for itself, then pays you.",
      plans: [
        { id: "p9", n: "9", title: "Payments for plans", line: "Upgrade online, receipts included.", size: "L", steps: [
          { t: "Choose an Israeli payment provider" },
          { t: "Monthly billing for featured and website plans" },
          { t: "Receipts and plan status in admin" },
        ], you: "Payment provider and tax details" },
        { id: "p25", n: "25", title: "CRM and pipeline", line: "Every lead, followed up.", size: "M", steps: [
          { t: "Leads from join and contact in one place" },
          { t: "Follow-up reminders and notes" },
        ]},
        { id: "p27", n: "27", title: "Analytics dashboard", line: "Searches, misses, conversions, at a glance.", size: "M", steps: [
          { t: "Search and miss trends" },
          { t: "Free to paid conversion" },
        ]},
        { id: "p12", n: "12", title: "Actions on the card", line: "Book, order, join the waiting list.", size: "L", steps: [
          { t: "Booking for clients that take appointments" },
          { t: "Ordering for food clients" },
          { t: "Waiting lists" },
        ]},
        { id: "p47", n: "47", title: "WhatsApp smart assistant", line: "Answers, books and takes orders, day and night.", size: "L", ai: true, steps: [
          { t: "Answers common questions from the card" },
          { t: "Takes bookings and orders" },
          { t: "Hands over to the owner when needed" },
        ]},
        { id: "p56", n: "56", title: "Smart booking", line: "Fills cancellations from the waiting list.", size: "M", ai: true, steps: [
          { t: "Best free slot and reminders" },
          { t: "Waiting list fills cancellations" },
        ]},
        { id: "p57", n: "57", title: "Demand forecast", line: "Busy hours and staffing, for apps like YellowShifts.", size: "M", ai: true, steps: [
          { t: "Predict busy hours" },
          { t: "Suggest shifts" },
        ]},
        { id: "p58", n: "58", title: "Smart ordering", line: "The usual, in one tap.", size: "M", ai: true, steps: [
          { t: "Reorder the usual" },
          { t: "Order by voice" },
        ]},
      ],
    },
    {
      id: "s9",
      name: "Launch quality",
      tagline: "The bar every page has to clear.",
      plans: [
        { id: "p10", n: "10", title: "Accessibility and legal", line: "The Israeli standard, signed off.", size: "M", steps: [
          { t: "Full audit against the Israeli accessibility standard" },
          { t: "Final privacy and terms text" },
        ], you: "The legal facts" },
        { id: "p37", n: "37", title: "Design system", line: "Every new page premium by default.", size: "M", steps: [
          { t: "Documented components, colours, motion" },
          { t: "One place to change the look" },
        ]},
        { id: "p29", n: "29", title: "Content tools", line: "Landing and story text edited in admin.", size: "M", steps: [
          { t: "Edit landing, showroom and story from admin" },
        ]},
        { id: "p18", n: "18", title: "Smarter map", line: "Open now on the map, layers, routes.", size: "M", steps: [
          { t: "Open now and categories as layers" },
          { t: "Your town offline" },
        ]},
        { id: "p36", n: "36", title: "Install on the home screen", line: "Darb as an app, without the store.", size: "S", steps: [
          { t: "Installable web app" },
          { t: "Recently viewed places offline" },
        ]},
        { id: "p38", n: "38", title: "Real people testing", line: "Hebrew and Arabic speakers, fixing what confuses them.", size: "S", steps: [
          { t: "Five sessions in Hebrew, five in Arabic" },
          { t: "Fix the top ten findings" },
        ]},
      ],
    },
    {
      id: "s10",
      name: "Everywhere",
      tagline: "In every pocket.",
      plans: [
        { id: "p11", n: "11", title: "The Darb app", line: "iPhone and Android: near me, search, cards, notifications.", size: "L", steps: [
          { t: "Expo app sharing Darb's code" },
          { t: "Near me, search and cards" },
          { t: "Push notifications" },
          { t: "Store listings in three languages" },
        ], you: "Apple and Google developer accounts" },
      ],
    },
    {
      id: "s11",
      name: "The real Darb",
      tagline: "The day everyone enjoys it.",
      finale: true,
      plans: [
        { id: "launch", n: "★", title: "Launch day", line: "Darb, working, and loved.", size: "M", steps: [
          { t: "1,000 real businesses live in the north", done: true },
          { t: "50 claimed by their owners" },
          { t: "5 paying clients beyond the first four" },
          { t: "Every page passes speed, accessibility and copy checks" },
          { t: "Launch post in Hebrew, Arabic and English" },
          { t: "Celebrate with Lama" },
        ]},
      ],
    },
  ],
};

/* Why Darb: the value it adds, said plainly, for pitches and for the hard days. */
window.DARB_WHY = {
  line: "Ask the way you'd ask a friend, in your own language, and get the real answer.",
  pillars: [
    { n: "01", title: "Built for the society here", body: "Hebrew, Arabic and English as equals, Arabic in local dialect. Sakhnin, Nahf and Daliyat al-Karmel matter as much as Tel Aviv." },
    { n: "02", title: "Search that understands people", body: "\"Gluten-free shawarma\" finds the dish inside Caramel. \"EV charging\" finds the stations that have it. Others search names; Darb searches what is inside." },
    { n: "03", title: "Honest by design", body: "No paid ranking dressed up as relevance. Strict facts stay strict. No dead ends: the closest real option, with its distance. Open now, computed every minute." },
    { n: "04", title: "Every business looks like itself", body: "Its own colour, logo, icons, photos and live screen. A small shop looks as premium as a chain." },
    { n: "05", title: "Darb builds, not just lists", body: "From a free card to the business's own app: Caramel, Raghad Beauty, YellowShifts for Paz. A directory and the studio behind it." },
    { n: "06", title: "Joining takes two minutes", body: "Paste a Google Maps link or tap \"I'm at my business now\". The smart form fills the card; you approve; it's live." },
    { n: "08", title: "Real data, at scale", body: "13,256 real businesses in the north from official government data and OpenStreetMap, each with its source recorded. No examples, no filler." },
    { n: "07", title: "A map that feels like a place", body: "Daylight, only the land Darb serves, near me with live distances, towns that open into businesses." },
  ],
  rivals: [
    { name: "Easy / Dapei Zahav", good: "Huge lists, phone numbers", gap: "Ads first, generic cards, little Arabic, no product" },
    { name: "Google Maps", good: "Everything, reviews", gap: "Generic, weak on Arab towns and small shops, never builds for the business" },
    { name: "Waze", good: "Driving", gap: "Not for discovering businesses" },
    { name: "Wolt / 10bis", good: "Delivery", gap: "Only restaurants that pay commission" },
    { name: "Instagram", good: "Where many businesses live", gap: "You must already know the account; no search by need, hours or place" },
  ],
  gaps: [
    { gap: "13,256 businesses in the north, thin in Arab towns and small trades", fix: "Owners claiming cards, field collection, WhatsApp joining", plans: "20 · 22 · 6" },
    { gap: "No reviews yet", fix: "Real reviews with photos and owner replies", plans: "14 · 44" },
    { gap: "Not known yet", fix: "SEO, share cards, QR stickers in shop windows", plans: "8 · 32" },
    { gap: "No app in the stores", fix: "Install on the home screen, then the Darb app", plans: "36 · 11" },
  ],
  forPeople: "Ask the way you'd ask a friend, in your own language, and get the real answer: what's open, what's close, what's actually inside.",
  forOwners: "A card that looks like you, free, in two minutes, and a partner that can build you your own app when you're ready.",
  focus: "Darb now has the breadth: 13,256 real businesses in the north. The next win is depth: owners claiming their cards, filling phones, hours and photos, and the Arab towns that open maps barely cover.",
};
