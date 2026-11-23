# Darb for iPhone

A SwiftUI app with a widget extension. The project file is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate                      # writes Darb.xcodeproj
open Darb.xcodeproj                    # then Run in Xcode, or:
scripts/run.sh                         # build, install and launch on the iPhone 17 Pro Max simulator
scripts/run.sh 20:30                   # the same, with the clock fixed at 20:30 (night)
scripts/run.sh 09:18 -darbLangOnce ar  # day, in Arabic
```

## The look

The world follows the hour, not the phone's setting: paper under a Galilee sky by day, ink by night. The person can
also fix it to light or dark in the settings.
A need's colour is the only strong colour, and it is used as light: the field behind the place you are looking at, the glow behind an object.
Corners are continuous (34 stage, 26 card, 22 tile, 16 control). It all lives in `Darb/Design`.

**Type** (`Design/Type.swift`). Three bundled faces, chosen by the language in use: Heebo for Hebrew, Cairo for Arabic,
Ubuntu for English. Figures (minutes, prices, counts) are Ubuntu with tabular digits in every language. Every size is
relative to a text style, so it grows with the person's text size. `scripts/fetch-fonts.sh` fetches the faces from
the google/fonts repository; each family's licence is bundled beside it and can be read in the app (About, typefaces).

**Icons.** No emoji anywhere. SF Symbols in one weight (`Font.symbol`), each on the same small tile, and Darb's own
drawn signs where a system symbol would not belong: the menu sign, the mark, the 3D objects.

**Motion** keeps three rules: one thing moves at a time, nothing passes behind or through anything else, and nothing bounces.
A tile grows into its page carrying only what the two share: the need's colour, its object and its name. The page
arrives as the need's own title card; only when everything is still does that card give way, where it stands, to the
nearest place and its own picture. Leaving is the same backwards. Reduce Motion turns it all into plain cuts and fades.

## The screens

- **Home** (`Features/Home`): one screen, taps only. The valley at this hour, the paid placement, the lead card, nine equal tiles, search and the advertising strip.
  The valley is the towns around the person in their real direction and distance: a few houses each, with as many marked open (a coloured roof by day, a lit window by night) as the share of the town that is open now. The largest towns carry their name and the number open in them.
- **Place** (`Features/Place`): the answer as a card you flip through, then the week, the details and, for a paying business, its own menu or prices. The way there stays in reach at the bottom.
- **Menu** (`Features/Menu`), behind Darb's own menu sign in the header: the language, where you are, kept places, settings, plans, joining, contact, about, terms and privacy. Every page opens inside the app.
- **Town and location** (`Features/Towns/TownChooser.swift`): the location button, and a search over every town.
- **Settings** (`Features/Settings`), **plans** (`Features/Plans`), **first run** (`Features/Onboarding`), **contact** (`Features/Contact`), **join** (`Features/Join`), **terms, privacy and about** (`Features/Legal`).
- **Search**, **towns of a need**, **everything else**, **splash**.
- **Widget** (`DarbWidget`) for the Home Screen and the Lock Screen, and **Siri and Spotlight** (`Features/Intents`): "what is open now".

## Language

Hebrew, Arabic and English, chosen in the app (first run, menu, settings), not by the phone. Hebrew and Arabic read
right to left, English left to right. Everything follows: copy, typeface, dates, and the data itself (business, kind
and town names come in all three).

- `Darb/Resources/Localizable.xcstrings` holds every phrase. A phrase the app wrote itself is keyed by its Hebrew; a
  phrase taken from the website is keyed by where it lives there (`web.contact.form.name`).
- `scripts/sync-copy.mjs` copies the website's own words (the shared messages, the contact and join forms, the landing
  page, the location request) into the catalog, writes the terms and the privacy policy to `legal.json`, and with
  `--check` fails when the code uses a phrase the catalog does not have in all three languages.
- In code, `L("...")` gives the phrase in the language in use (`Data/Lang.swift`).
- Arabic is the local spoken dialect, in the website's own vocabulary.

## Where the person is

Everything (the valley, the tiles, the minutes, the order) is measured from one point, `Store.origin`: the person's
position while the app is in use (`Data/LocationService.swift`), or the centre of the town they chose. The app asks
for the position only when the person asks for it. Outside the area Darb covers, the chosen town is used and the
app says so. The widget and Siri measure from the point the app last used.

## Data

`scripts/export-data.py` writes the bundled data from `packages/seed/data`:

| File           | What                                                                                                                                    | Read                               |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `darb.json`    | every real business in the north (13,255), 212 kinds, 521 towns, in three languages, as columns                                         | when the app opens                 |
| `needs.json`   | the same, for the nine everyday needs only                                                                                              | by the widget and Siri             |
| `details.json` | phone, WhatsApp, website, address, attributes, social links                                                                             | off the main thread, after opening |
| `screens.json` | the sample page of each kind, always labelled as a sample                                                                               | with the details                   |
| `promo.json`   | the plans with features, prices and notes, the pricing page's copy, the paid placements (none yet), the profiles of Darb's real clients | when the app opens                 |
| `legal.json`   | terms and privacy, from `scripts/sync-copy.mjs`                                                                                         | when one is opened                 |

The showroom examples in `businesses.json` are made up, so they are never bundled. A business whose source gives no
hours gets its sector's usual week and is marked `demo`; the app labels those as sample hours wherever it shows them.

## The Darb API

The contact form and the join form post to the API the website uses (`Data/API.swift`, `https://api.darb.co.il`):
`POST /inquiries` and `POST /join`, with the bodies `packages/contracts` describes. When the API cannot be reached the
form says so and offers the same message as a ready email.

## The rules the code keeps

- **The honest answer is never for sale.** Tiles and the lead card always show the truly nearest open place. Payment buys a labelled placement beside it, a richer page, and never rank (`Data/Promo.swift`).
- **Nothing is made up.** No sponsor, no photo, no logo, no rating. Sample hours are labelled. Empty picture slots stay empty.
- **A place's picture is its own** (`Data/ArtResolver.swift`): its logo, else its cuisine, its name, its kind, its need, else a symbol on its sector's colour.
- **The lead card follows the person**, not a sponsor.
- **Copy:** no dashes, never the words the product rules exclude, no names of languages or faiths. The tests check the catalog for this.

## Launch arguments for testing

| Argument                                                             | What it does                                                                                                                                                                           |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-darbTime 20:30`                                                    | Fixes the clock                                                                                                                                                                        |
| `-darbLangOnce ar`                                                   | The language for this run (`he`, `ar`, `en`)                                                                                                                                           |
| `-darbAppearance dark`                                               | The look for this run (`hour`, `light`, `dark`)                                                                                                                                        |
| `-darbLocation 32.919,35.295`                                        | Stands the person at a point                                                                                                                                                           |
| `-darbTownOnce nazareth`                                             | Stands the app in a town for this run                                                                                                                                                  |
| `-darbOnboard YES`                                                   | Shows the first run again (`-darbOnboardStep 1` starts on a later step); `-darbOnboarded YES` skips it                                                                                 |
| `-darbSkipSplash YES`                                                | Opens without the splash                                                                                                                                                               |
| `-darbRoute need:fuel`                                               | Opens a screen: `need:<key>`, `kind:<slug>`, `business:<id>`                                                                                                                           |
| `-darbSheet search`                                                  | Opens a sheet or a page of the menu: `search`, `kinds`, `town`, `menu`, `settings`, `saved`, `plans`, `about`, `join`, `contact`, `terms`, `privacy`, `fonts`; `towns` on a place page |
| `-darbQuery pizza`                                                   | Fills the search field                                                                                                                                                                 |
| `-darbTab hours`                                                     | Opens the place page on `hours` or `info`                                                                                                                                              |
| `-darbPick 3`                                                        | Turns the place page to the third place                                                                                                                                                |
| `-darbLead bank`                                                     | Sets the need the lead card answers                                                                                                                                                    |
| `-darbAutoBack 2.2`                                                  | With `-darbRoute`: opens the screen after a moment and closes it again, for filming the transition                                                                                     |
| `-darbAPI http://127.0.0.1:8787`                                     | Points the forms at another server; `-darbFormFill YES` and `-darbFormSend YES` fill and send a test message there                                                                     |
| `-darbReset YES`                                                     | Forgets what the device remembers                                                                                                                                                      |
| `-darbDemoMedia YES`, `-darbDemoProfile all`, `-darbDemoSponsor YES` | **Demo.** Placeholder pictures, paid pages and placements, each marked as a demo                                                                                                       |

`scripts/shot.sh out.png 20:30 need:food -darbLangOnce en` saves a screenshot. Simulate a position with
`xcrun simctl location <udid> set 32.919,35.295`, or with `-darbLocation`.

The app also opens `darb://need/food`, `darb://kind/schools` and `darb://business/<id>`.

## Scripts

| Script                              | What it does                                                                           |
| ----------------------------------- | -------------------------------------------------------------------------------------- |
| `scripts/export-data.py`            | Writes the bundled data from `packages/seed/data`                                      |
| `scripts/sync-copy.mjs`             | Brings the website's copy and legal pages into the app; `--check` verifies the catalog |
| `scripts/fetch-fonts.sh`            | Fetches the three typefaces and their licences                                         |
| `scripts/run.sh`, `scripts/shot.sh` | Build and launch; launch and screenshot                                                |

The app group `group.il.co.darb.app` lets the widget read the language and the place chosen in the app.

Progress and what is next: [PROGRESS.md](PROGRESS.md).
