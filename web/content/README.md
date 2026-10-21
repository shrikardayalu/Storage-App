# Content

Guides live in `guides/` as one Markdown file per page. The file name is the URL slug: `guides/compress-videos-iphone.md` → `/guides/compress-videos-iphone`. Every guide is prerendered at build time, added to the sitemap, RSS feed, `/llms.txt`, the guides hub, and the footer, with no extra wiring.

The build **fails** if a guide is malformed, links to a page that doesn't exist, lists a missing related guide, or targets a `primaryKeyword` another guide already owns. A failed build means nothing broken ships.

## Frontmatter

```yaml
---
title: "How to Compress Videos on iPhone to Save Space"   # H1. Match the searcher's words.
seoTitle: "How to Compress Videos on iPhone (Without Deleting Them)"  # optional <title>, aim ≤ 60 chars
description: "Keep the video, lose most of the file size…"  # meta description, aim ≤ 155 chars
topic: videos               # one of the ids in src/lib/topics.ts
primaryKeyword: "compress video iphone"  # one guide per keyword; prevents cannibalization
published: 2026-10-20
updated: 2026-10-20         # bump whenever the steps are re-checked or changed
illustration: ill-compress  # any file in public/illustrations (no extension)
related:                    # slugs, shown first under "Keep reading"
  - iphone-storage-full
quickAnswer: "Two to four sentences that fully answer the query. Bold the key menu paths."
ctaTitle: "Compress videos in a couple of taps"           # optional, tied to this problem
ctaBody: "{app} shows your largest videos first and…"     # optional
faq:                        # optional; rendered on the page and as FAQPage schema
  - q: "Does compressing a video reduce quality?"
    a: "Yes, somewhat…"
draft: true                 # optional; drafts are skipped entirely
---
```

`{app}` anywhere in a guide is replaced with the app's current name (`NEXT_PUBLIC_APP_NAME`).

## Body

Standard Markdown (GitHub-flavored: tables, lists, links).

- Use `##` for main sections. They become the "On this page" table of contents and get stable anchor ids.
- Put `<!-- cta -->` on its own line where a mid-article call to action belongs: right after the section where the reader has the problem fresh and the built-in fix has shown its limits, typically 40–60% of the way down. One or two per guide.
- Link internally with root-relative paths: `[how to compress videos](/guides/compress-videos-iphone)`. Aim for 2–4 contextual links out of every guide, and add a link **into** each new guide from at least one existing guide.
- Link out to Apple Support when it's the authority for a claim.

## Quality bar

Every guide answers a real search query, verified on a current iPhone:

1. **Answer first.** The `quickAnswer` stands alone. If it's the only thing someone reads (or an AI engine quotes), they're helped.
2. **Built-in tools before the app.** The app is the shortcut, never the only path.
3. **Never invent.** No made-up statistics, test results, app capabilities, or competitor facts. Never imply any app can clear System Data, other apps' caches, or "boost RAM".
4. **One page per intent.** If a query is already covered, improve that guide instead of writing a new one.
