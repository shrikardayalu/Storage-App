# Carousels

Turns a short JSON file into a swipeable carousel for TikTok (1080 x 1920) and
Instagram (1080 x 1350), in the same look as the site and the App Store art.
A model (or you) writes the words; the template does the design, so every
slide comes out on-brand and the text is always spelled right.

```bash
node marketing/carousels/render.mjs marketing/carousels/carousels/storage-eaters.json
```

```bash
node marketing/carousels/render.mjs --all
```

Add `--format tiktok` or `--format instagram` for one size, or `--check` to
validate without rendering. It needs Node 22+, Chrome or Edge, and an internet
connection (the fonts come from Google Fonts). No npm packages.

Output lands in `out/<name>/` (git-ignored):

- `tiktok/01.png …` and `instagram/01.png …`: the slides to upload, in order.
- `overview-tiktok.png`, `overview-instagram.png`: the whole carousel at a glance.
- `caption.txt`: the caption and hashtags to paste into the post.

In Claude Code, `/carousel <topic>` writes a new one, renders it and checks it.

## Files

| File | What it is |
| --- | --- |
| `carousels/*.json` | One carousel each. The file name becomes the output folder. |
| `brand.json` | App name, icon, and the default last slide (button text, link). Change the link here at launch. |
| `template.html` | The slide designs and safe areas. |
| `render.mjs` | Checks the JSON and screenshots each slide with headless Chrome. |

## The JSON

```json
{
  "caption": "One or two sentences for the post.",
  "hashtags": ["iphonetips", "iphonestorage"],
  "slides": [
    { "type": "hook", "kicker": "iphone storage full?", "title": "5 things *quietly* eating your storage", "art": "phone-sparkle" },
    { "type": "cta" }
  ]
}
```

Three to ten slides. Start with a `hook`, end with a `cta`.

| Type | Fields (bold = required) | Use it for |
| --- | --- | --- |
| `hook` | **title**, kicker, body, art | Slide 1. The reason to swipe. |
| `point` | **title**, number, kicker, body, tip, source, art | One idea per slide. `tip` is a hand-written sticker. |
| `stat` | **value**, **label**, **source**, kicker, body | One big number, e.g. `"400 MB"`. |
| `list` | **title**, **items** (2 to 5), kicker | A recap or checklist. |
| `screen` | **title**, **image**, kicker, note | An app screenshot in a phone. `note` is a short hand-written aside. |
| `cta` | title, body, button, url | The last slide. Empty fields come from `brand.json`. |

Every slide also takes `theme`: `cream`, `soft`, `mint` or `dark`. Leave it
out and the slides alternate on their own.

**Text marks.** `*word*` is hand-written, `==word==` is highlighted,
`**word**` is bold. Use one hand-written word or phrase per headline at most.

**Pictures.** `art` is the name of an illustration in
`../app-store/art` without `ill-` (for example `piggy`, `video`,
`screenshot`, `compress`, `trash`, `shield-check`, `stack-large`).
`image` is the name of a screenshot in `../app-store/screens` (for example
`home-light`), or a path to a PNG next to the JSON file, such as
`"shots/my-results.png"`.

The renderer warns when a field is longer than reads well, and shrinks the
type to fit if it has to. If it says a slide was shrunk, cut words.

## Writing rules

These matter more than the design. A carousel that overpromises costs trust
and reviews.

1. **Only true things.** Never invent a statistic, a test result or a
   testimonial. Every `stat` slide needs a `source`, and the number must come
   from a guide in `web/content/guides/` (those were checked) or from a real
   run on a real phone.
2. **Only what the app does.** Features and the free/Pro split are in
   `docs/PRICING.md`. The scan is free; shrinking videos, Live Photos to
   stills and screenshot re-save are Pro, so never call those free. Never say
   the app clears System Data or other apps' caches.
3. **Screenshots are demos.** The numbers in `../app-store/screens` are
   sample data. Show them as "what it looks like", never as "I freed 5 GB".
   For a results post, use a screenshot from a real cleanup.
4. **Teach first.** Most slides should help someone who never installs the
   app. The app appears on the last slide, or as the easier way to do a step.
5. **One idea per slide,** readable in about three seconds. Short words, no
   jargon, sentence case.
6. **The hook is a specific promise or a surprise** about the viewer's own
   phone ("5 things quietly eating your storage"), not a claim about the app.
7. **The caption** adds one useful line and a reason to save or share. Three
   to five hashtags.

## Ideas that fit

- Lists: what fills an iPhone, settings worth changing, things safe to delete.
- One surprising number, explained (4K video sizes, Live Photos, PNG screenshots).
- A how-to from a guide, one step per slide, using built-in iOS tools.
- Myths: "turning off Live saves space", "cleaner apps clear System Data".
- A walk through the app with `screen` slides.

Each guide in `web/content/guides/` is already a checked source for one
carousel.

## Posting

Upload the slides in order as a photo post. On TikTok, add a sound from the
app when posting; photo posts without one reach fewer people. On Instagram,
pick the 4:5 crop. Until the App Store launch the last slide points at the
waitlist; after launch change `button` and `url` in `brand.json`.
