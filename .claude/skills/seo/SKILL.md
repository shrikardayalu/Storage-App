---
name: seo
description: Research, write, and publish one SEO guide for simpleshrink.com, or improve an existing one. Use when asked for an article, guide, blog post, SEO content, keyword research, internal linking, a content refresh, or to "run the SEO engine".
---

# SEO

One run does one thing well: a new guide, or a real improvement to an existing
page. The goal is search traffic that turns into SimpleShrink installs, earned
by pages that would be worth reading even if the app didn't exist.

If the arguments name a topic or keyword, use it. Otherwise choose one (step 2).

Read these first, every run. They are binding:

- `web/content/README.md`: the file format and quality bar.
- `automation/README.md`: pace, topic rings, how results are measured.
- `automation/backlog.md` and the top of `automation/log.md`.

## 1. Check the pace

List the `published` dates in `web/content/guides/*.md`.

- A guide already published today, or 5 in the last 7 days: no new guide.
  Improve an existing page instead (step 2, options b to d).
- Otherwise a new guide is allowed. Don't publish on the same weekdays every
  week; an uneven rhythm is intended.

The build enforces the ceiling, so don't work around it with a false date.

## 2. Pick one action

With Search Console data (`gum` if installed; otherwise ask the user for an
export, or skip to the backlog):

a. A query with impressions that no page targets: new guide.
b. A page with impressions and a low click rate: rewrite `seoTitle`,
   `description`, and `quickAnswer`.
c. A page at positions 5 to 20: make it more complete (missing sub-question,
   table, FAQ) and link to it from more pages.
d. Guides that should link to each other and don't: add the links.

Without data, take an `open` row from the backlog. Keep the week mixed: about
two core, one or two adjacent, a comparison every week or two. Check the log
so you don't write three of one kind in a row.

**The tie-back test.** A topic qualifies only if someone who finishes the page
plausibly has a storage, photo, or video problem the app helps with, and the
page can link to two core guides without forcing it. iPhone camera settings,
iCloud, backups, sharing large videos, and switching phones pass. General
iPhone news, Android, and unrelated how-tos fail.

## 3. Research the keyword

There's no keyword-volume tool here, so use the search results as evidence.

1. Search the candidate phrase and two or three variations in the way a
   person would type them. Note the wording that recurs in titles: that's the
   phrase to target.
2. Read what ranks. What kind of page is it (steps, explanation, comparison,
   list)? Match that intent. If the first page is all Apple Support and major
   publishers answering the exact question well, pick a narrower version
   ("…without a computer", "…on iPhone 16", "…for WhatsApp") or another topic.
   Thin, outdated, or content-farm results mean there's room.
3. List what the ranking pages leave out or get wrong, and the related
   questions people ask ("People also ask", forum threads). Those become
   sections and FAQ entries.
4. Check `primaryKeyword` across `web/content/guides/` and `web/content/compare/`.
   If a page already owns this intent, improve that page. Never write a
   second page for the same intent.

Settle on: one `primaryKeyword` (lowercase, as searched), two to four
secondary phrasings to use naturally in headings, and the page type.

## 4. Gather the facts

Every factual claim needs a source you opened during this run.

- iPhone behavior and menu paths: Apple Support or the iPhone User Guide.
  Fetch the page; don't rely on memory. Menus move between iOS versions (app
  settings now live under **Settings → Apps**).
- Sizes and numbers: Apple's own figures, or plain arithmetic on them shown
  in the open. If Apple publishes no number, don't supply one. Tell the
  reader how to see it on their own phone instead.
- The app: `docs/PRICING.md` and the site's own pages. Only what it ships.
- Competitors: their App Store listing or site, cited, with the date checked.

Can't source it? Leave it out, or state it as conditional ("on many
iPhones…") and list it under **device check** in the log. Never invent
statistics, test results, or capabilities. Never say or imply any app can
clear System Data, clear other apps' caches, or speed up the phone.

## 5. Write

File: `web/content/guides/<slug>.md`. Slug: the keyword in kebab-case, short,
no dates or filler words. Frontmatter per `web/content/README.md`.

**Search snippet**

- `title` (the H1): the searcher's words, plus what they get.
- `seoTitle`: 60 characters or fewer, keyword near the front, no clickbait.
- `description`: 155 characters or fewer; says what the page answers.

**Quick answer.** Two to four sentences that fully answer the query, with
menu paths in bold. Someone who reads only this, or an AI engine that quotes
only this, has been helped. Don't tease.

**Body**

- Open with one or two sentences that show you understand the situation. No
  "In today's digital world".
- `##` sections named the way people ask. Each should make sense on its own,
  since search engines and AI answers lift single sections.
- Numbered steps for anything done in order, one action per step, exact
  button names in bold. Tables for comparing options or sizes.
- Built-in iPhone tools first, and say honestly when they're enough. The app
  is the shortcut, never the only way.
- 700 to 1,300 words. Stop when the question is answered; never pad.
- Plain language, second person, short paragraphs. Read
  `web/content/guides/iphone-storage-full.md` for the voice.

**The app**

- One `<!-- cta -->`, placed right after the section where the built-in route
  shows its limit. A second only in a long guide.
- `ctaTitle` and `ctaBody` name this page's problem, not a generic pitch. Use
  `{app}` for the name.
- At most one or two mentions of the app in the body. An adjacent-ring page
  can have none in the body: the CTA and the links to core guides do the work.

**FAQ.** Three to five real follow-up questions not already answered in the
body, each answered in one to three sentences. They become FAQ schema.

## 6. Link it in

Internal links are how a new page gets found and how authority reaches the
pages that convert.

- **Out:** two to four links in the body to other guides, in sentences where
  the reader would want them. An adjacent-ring guide must link to at least
  one core guide (`compress-videos-iphone`, `iphone-storage-full`,
  `delete-duplicate-photos-iphone`, `live-photos-storage-iphone`,
  `delete-all-screenshots-iphone`).
- **In:** edit at least one existing guide, two if it's natural, to link to
  the new one. Find the sentence that already mentions the subject and link
  there. A new page with no links in is an orphan.
- **Anchor text** describes the destination ("how to compress videos on
  iPhone"), never "click here" or "this guide". Vary it between pages.
- `related:` two or three slugs, closest topic first.
- Link out to the Apple Support page behind a key claim, once.
- Comparison pages: link from a guide only where choosing an app is the topic.

## 7. Verify

1. Re-read the draft against the sources. Each number, menu path, and claim
   about the app either traces to a source or comes out.
2. `npm run build` in `web/`. Fix every error; the build checks links,
   frontmatter, duplicate keywords, and pace.
3. Check lengths: `seoTitle` ≤ 60, `description` ≤ 155.
4. If steps couldn't be confirmed from a source, set `draft: true` and say so
   in the log, instead of publishing a guess.

## 8. Publish and record

1. Add an entry at the top of `automation/log.md`: date, action, slug,
   keyword, why this one, sources, links added, device checks, and a date
   four weeks out to review it.
2. Update `automation/backlog.md`: mark the row `published` with the slug,
   and add any good ideas the research turned up as new `open` rows.
3. Commit only the files this run touched, to `main`, and push. No branches,
   no pull requests. The push deploys the site.
4. Tell the user: the URL, the keyword and why, each factual claim with its
   source, and anything flagged for a device check.

## Improving an existing page

- Bump `updated` only when facts or steps were re-checked or changed.
- Never change a published slug. The URL is what has earned its ranking.
- A title or description rewrite is a test: log the old and new versions and
  compare click rate after three to four weeks.
- When a guide goes out of date (a new iOS moves a menu), fixing it comes
  before any new guide.

## Never

- Publish something that reads like every other result with the words moved
  around. If the draft adds nothing the ranking pages lack, pick another topic.
- Repeat the keyword unnaturally, hide text, or write a page for a keyword
  with no real answer behind it.
- Create near-duplicate pages that swap one word (a page per iPhone model, a
  page per city). That is the pattern search engines penalize.
- Put a secret, an API key, or a person's email in the repo. It's public.
