# App Store Optimization pipeline

Three steps, each one command, no npm packages (Node 22+ and Chrome).

| Step | Command | You edit | It makes |
|---|---|---|---|
| 1. Research keywords | `node marketing/aso/research.mjs` | `research/seeds.json` | `research/report.md`, `research/data.json` |
| 2. Write and check the listing | `node marketing/aso/check.mjs` | `metadata.json` | `metadata.md` (paste sheet) |
| 3. Render screenshots | `node marketing/aso/screenshots/render.mjs --all` | `screenshots/sets/*.json` | `screenshots/out/<set>/<locale>/<size>/*.png` |
| Header and search results assets | `node marketing/aso/creative/render.mjs` | `creative/template.html` | `creative/out/header.png`, `creative/out/search.png` |

## 1. Research

`research.mjs` uses only Apple's public endpoints: App Store autocomplete,
the iTunes Search API and the public app pages. For every seed phrase in
`research/seeds.json` it collects what autocomplete suggests in the US, UK,
Canada and Australia, searches the US store for each phrase, and records the
top 10 apps with their titles, subtitles and rating counts.

`research/report.md` ranks phrases by a score: demand (is it suggested, in
how many stores, how high) discounted by difficulty (how many of the top 10
have the phrase in their title, and how many ratings they have). Apple
publishes real search volume only inside Apple Ads, so demand is a proxy.
Once the app is live and has an Apple Ads account, check the top phrases
against the popularity numbers there.

The first run takes about five minutes because the Search API allows about
20 calls a minute. Answers are cached in `research/cache/` for a week;
`--fresh` ignores the cache. To research a new angle, add seeds. `relevant`
and `irrelevant` in the seeds file filter what autocomplete brings back.

## 2. Metadata

`metadata.json` holds the name (30), subtitle (30) and keyword field (100)
for each localization, plus `targets`: the phrases that localization is
built to match. `check.mjs` fails on anything over a limit and on any target
that can't be matched, and prints a note for every wasted character.

The rules it checks come from how App Store search reads a listing:

- **One localization is one pool.** Apple pools the name, subtitle and
  keyword field of a localization and builds phrases from the words itself.
  A word is needed once; repeating it, or its plural, is waste. Use single
  words separated by commas with no spaces.
- **Phrases don't cross localizations.** "video" in one localization and
  "compressor" in another doesn't match "video compressor". So each
  localization is written around one theme.
- **A storefront reads several localizations.** The US store indexes English
  (U.S.) and nine more; a US shopper whose iPhone is in English still only
  *sees* the English (U.S.) listing. So the other nine carry extra themes
  without the main listing looking stuffed. The table lives in `check.mjs`
  (`STOREFRONTS`), copied from
  [Apple's list](https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/).
- **Name beats subtitle beats keywords** for ranking weight, so each
  localization puts its most wanted phrase in the name.

Two things to know about this setup:

- The app is English-only, so every localization is written in English. A
  shopper in the US whose iPhone is set to Spanish sees the Spanish (Mexico)
  listing, in English. The same listings are what Mexico, France, Brazil and
  the other home countries of these languages see.
- App Review reads the name and subtitle of every localization. Keep each
  one a true description of the app, which they are; don't turn them into
  word lists.

## 3. Screenshots

A set is a JSON file in `screenshots/sets/`: an ordered list of shots. To
test a new idea, copy `control.json`, change the headlines, order or
screens, and render it. A full set takes a few seconds.

```json
{ "layout": "phone", "theme": "cream", "headline": "Full iPhone?\n*shrink it,*\ndon't delete.",
  "screen": "onboarding-light", "art": ["video", "compress"], "doodle": "arrow" }
```

| Field | Values |
|---|---|
| `layout` | `phone` (headline, phone below), `hang` (phone hanging from the top, headline below), `promises` (illustration and checklist, no phone) |
| `theme` | `cream`, `mint`, `soft`, `dark` |
| `headline` | `\n` starts a line; `*word*` is hand-written. It shrinks to fit, and the renderer says so if it had to shrink a lot. |
| `screen` | a file name in `marketing/app-store/screens/` without `.png` (a 1320 × 2868 capture from the app) |
| `art` | illustration names from `marketing/app-store/art/` without `ill-` (two for `phone`, three for `hang`, one for `promises`) |
| `note` | a hand-written line (`phone`, `hang`) |
| `items` | the checklist (`promises`) |
| `doodle`, `blob`, `phoneWidth`, `phoneTop` | small layout options; see `control.json` |

Sizes: by default it exports 6.9" (1320 × 2868), which is the one App Store
Connect asks for and scales down for smaller iPhones, and 6.5" (1284 × 2778),
the accepted alternative. `--size all` adds 6.3" and 6.1". The PNGs have no
transparency, as Apple requires. The app is iPhone-only, so there are no iPad
sizes.

Other languages: add `"locales": { "es-MX": [ { "headline": "..." }, {}, ... ] }`
to a set, one entry per shot, and it renders that language too. Localizations
without their own screenshots show the English (U.S.) ones, which is what
the current English-only setup relies on.

New app screens come from CI's **Screenshots** artifact (or a 6.9"
simulator); drop the PNG in `marketing/app-store/screens/`.

### Running an A/B test

In App Store Connect → **Product Page Optimization**, create a test, upload
`out/control/en-US/6.9/` as the original and another set as a treatment.
Change one thing per set (the first shot's headline, or the order) so the
result says what worked. Only the first three shots show in search results,
so that's where a test moves the most.
