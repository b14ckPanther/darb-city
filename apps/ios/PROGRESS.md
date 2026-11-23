# Darb for iPhone: progress

SwiftUI first, finished and tested on iPhone; the Kotlin (Android) app follows the same spec after.

## Milestone 1: the app runs (done)

- [x] Xcode project (XcodeGen `project.yml`), iOS 18+, Hebrew right to left, light and dark
- [x] Bundled data: at first 1,519 listings within 30 km of Sakhnin; now every business in the north (see round three)
- [x] All nine 3D objects, still and turning, plus the app icon in light and dark
- [x] Splash: the mark rises out of the night and flies into the header
- [x] Home: the valley at this hour (each light is a place open now), lead card, eight need tiles, "everything else", search
- [x] Place page: zoom from the tile, every option at once, pages, town picker, menu / fuel board / services / branch, hours, details, navigate and call
- [x] Search in plain words (name, kind, town), also inside a need
- [x] Every other kind: area, then kind
- [x] Unit tests: opening hours, search (10 passing)
- [x] Run and screenshot scripts (`scripts/run.sh`, `scripts/shot.sh`)

## Redesign: the experience (done)

- [x] One look for the whole app that follows the hour: paper by day, ink by night (`Design/Theme.swift`)
- [x] Home: the valley with a path to the lead answer, nine tiles of one size, search, all on one screen and taps only
- [x] The lead card follows the person: the need they chose, else the one they open most at this hour, else the hour's order. It says which, and its name is a one-touch menu to change it
- [x] Place page: the answer as a card to flip through (swipe, or tap the row), with minutes, distance and direction, today's hours, the week, the details
- [x] A place's own picture everywhere a place is shown: logo, cuisine, name, kind, need, then a symbol (`Data/ArtResolver.swift`)
- [x] Search that shows what it understood (kind, town, name); towns by distance; every other kind by sector; a new splash
- [x] Money, by one rule: the honest answer is never for sale (`Data/Promo.swift`)
  - [x] Paid placements, always labelled "ממומן": on home, and first in the row on a need's page when the sponsor is at most 5 minutes further than the nearest. None are sold, so the slots show Darb's own card
  - [x] An advertising strip at the bottom of home, labelled "פרסומת"
  - [x] Profiles: logo, cover, three photos and a storefront picture free for every business; menu, prices and ordering for paying ones. Darb's four real clients have theirs
  - [x] Taps on navigate, call, order and open are counted per business on the device, ready to be sent to the API (`Data/Analytics.swift`)
- [x] Keep a place, share a place, "tell me when it opens" (a local notification, only for real hours)
- [x] Contact us and Darb for businesses, in the in-app browser
- [x] A widget for the Home Screen and the Lock Screen; "מה פתוח עכשיו" in Siri, Spotlight and Shortcuts
- [x] Open when you get there: answers check the hours at arrival
- [x] Ask before you drive: a prefilled WhatsApp message or a call, as the main button when the hours are not the business's own
- [x] Motion by three rules: one thing moves at a time, nothing passes behind anything, nothing bounces. A tile grows into its page and the content lands after it; closing is the reverse
- [x] Unit tests: 29 passing

## Round three: the owner's feedback (done)

| Stage | What | Status |
| --- | --- | --- |
| 1 | Fonts, icons and emoji, and the valley by day and by night | 100% |
| 2 | The full data and real location | 100% |
| 3 | The language switcher and multilingual data | 100% |
| 4 | Settings and the menu | 100% |
| 5 | Plans, first run, contact and join | 95% (join sends no photos yet) |
| + | The tile to page transition | 100% |

- [x] **The valley, day and night, as one drawing at two hours.** The towns around the person, a few houses each; as many are marked open as the share of the town that is open: a coloured roof by day, a lit window by night. The largest towns carry their name and the number open. The hills begin under the header, so its text always stands on clean sky, in every language and on the small phone
- [x] **Type**: Heebo, Cairo and Ubuntu bundled with their licences, chosen by language, all sizes relative to the text size
- [x] **No emoji and no decorative symbols**: one symbol weight, one icon tile, Darb's own menu sign; the sponsored card carries the mark, the ninth tile four small tiles
- [x] **Every business in the north**: 13,255 places, 212 kinds, 521 towns in three languages, from `scripts/export-data.py`; sample hours stay labelled
- [x] **Real location**: the location button, a clear request, a town picker with search over every town; everything is measured on the phone from where the person is
- [x] **Hebrew, Arabic and English**: a String Catalog for every phrase, the website's own words where it has them, right to left and left to right, multilingual data, a switch in the first run, the menu and the settings
- [x] **The menu**, designed: language, place, kept places, settings, plans, joining, contact, about, terms, privacy
- [x] **Settings**: language, town and location, look (by the hour, light, dark), reminders, navigation app (Waze, Apple Maps, Google Maps, only the installed ones), kept places, about, terms, privacy, contact, version
- [x] **Plans and prices**, native, from `plans.json` in three languages
- [x] **First run**: what Darb is and the language, what it answers, where you are; taps only, skippable
- [x] **Contact and join**, native forms posting to the Darb API, with a ready email when it cannot be reached
- [x] **Terms and privacy**, native, from the website's own text
- [x] **The transition**: the need's own card is what grows out of a tile and shrinks back into it; the place takes its place only when everything is still
- [x] Unit tests: 57 passing (export, location and distance, language, forms, valley layout, and the earlier ones)

Still open from this round:
- [ ] Join: logo and photo upload (the API has `/join/photos`) and the "find my business" lookup (`/join/lookup`)
- [ ] The widget and Siri use the place the app last measured from; they do not ask for the position themselves
- [ ] Street addresses from some sources exist in Hebrew only, and are shown as written

## Next: the experience

In this order.

1. [x] **Open when you get there.** Every answer checks the hours at arrival, not just now. If a place closes in 15 minutes and the drive is 20, it says so and offers the nearest that will still be open.
2. [x] **Ask before you drive.** A WhatsApp or call button with a message already written ("היי, ראיתי אתכם בדרב. אתם פתוחים עכשיו?"). It is the main button when a place has no hours or only sample hours.
3. [ ] **Special days.** Weekend and holiday hours per town, and a "שעות מיוחדות היום" note when today differs. No religion names in the copy. Needs data.
4. [ ] **Night essentials.** Duty pharmacies and emergency numbers from official sources only, brought up on their own late at night.
5. [ ] **Two-tap corrections.** "Closed for good", "hours wrong", "phone wrong", sent to the Darb team. This keeps the data honest.
6. [ ] **Reviews that can be trusted.** Quick tags (fast, clean, easy parking, friendly) and a photo, allowed only after the person actually navigated there. No anonymous star spam.
7. [ ] **"My usual places."** Saved, recent and frequent, one tap from home. Kept places exist; recent and frequent do not yet.
8. [ ] **Live Activity** on the Lock Screen and the Dynamic Island while driving to a place: minutes left and the closing time.
9. [ ] **Voice search** in Hebrew and Arabic, including mixed language.
10. [ ] **Offline.** The last data keeps working where there is no signal.
11. [ ] **Accessibility filters.** Wheelchair access, easy parking, delivery.
12. [ ] **Share a place as a rich card into WhatsApp**: name, logo, open until, a navigate link. Today a place is shared as its name and a Waze link.

## Milestone 2: the business card, deeper

- [ ] One business, several parts (fuel 24 hours, market until 22:00, car wash), each with its own hours and open light
- [x] Images: logo, cover, photos and storefront modelled and designed, finished without them; no business has given any yet
- [ ] Darb Deluxe businesses: live menu and prices from their own app, order or book button
- [x] Share a place; save places

## Milestone 3: live data

- [ ] Read from the Darb API instead of the bundled snapshot; any home town, real location
- [ ] Offline: keep the last data for use without a connection

## Milestone 4: people

- [ ] Add a business; suggest a fix
- [ ] Ratings and reviews, with moderation and reporting
- [ ] Visitor accounts

## Milestone 5: ship

- [x] Arabic and English
- [ ] Accessibility pass (VoiceOver, large text, contrast)
- [ ] Performance on real iPhones
- [ ] TestFlight, then the App Store
