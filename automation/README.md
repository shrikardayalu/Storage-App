# SEO engine

How the site grows through search: publish one genuinely useful answer at a time, link it into the library, and measure which pages turn readers into installs. Modeled on how Vaultaire grew.

The engine is three things:

| Piece | Where | What it does |
| --- | --- | --- |
| The skill | [`.claude/skills/seo/SKILL.md`](../.claude/skills/seo/SKILL.md) | The whole method: picking a keyword, checking the search results, writing, structure, internal links, verifying, publishing. Run it with `/seo` |
| The backlog | [`backlog.md`](backlog.md) | Candidate topics by cluster, with the keyword and how each ties back to the app |
| The log | [`log.md`](log.md) | What was published or changed, when, why, and what to check later |

Everything else is the website (`web/`), which already handles the technical side:

| Need | Where it lives |
| --- | --- |
| Authoring format and quality rules | [`web/content/README.md`](../web/content/README.md) |
| Guides | `web/content/guides/*.md`, one file per URL |
| Build-time checks | `web/src/lib/guides.ts` fails the build on broken internal links, missing related guides, bad frontmatter, a duplicate `primaryKeyword`, or publishing faster than the pace below |
| Discovery | `/sitemap.xml`, `/robots.txt` (search and AI crawlers allowed), `/guides/feed.xml`, `/llms.txt` |
| Structured data | Organization, WebSite, MobileApplication, Article, BreadcrumbList, FAQPage, CollectionPage (`web/src/lib/schema.ts`) |
| Conversion | Quick-answer box, inline CTAs at `<!-- cta -->` markers, sidebar, end-of-page CTA, mobile sticky bar |
| Attribution | Waitlist signups record the page and CTA position as `source`. After launch, App Store links carry a campaign token (`ct`) per page and position, visible in App Store Connect → App Analytics |

The canonical site is `https://www.simpleshrink.com`. `simpleshrink.com` and the old `simpleshrink.vercel.app` both redirect to it.

## Pace: 3 to 5 new pages a week

The site is new and has no search history, so it publishes **3 to 5 new guides a week, never two on one day, on uneven days and times**. The build enforces the ceiling (`PUBLISHING_PACE` in `web/src/lib/guides.ts`): a sixth guide in any 7 days fails the build.

Google has no rule against publishing daily. What it acts on is many pages made mainly to rank, with little original value ("scaled content abuse"). A brand-new domain that adds a page every day at 6:07 looks like that, and it also means each page gets less care. A slower, uneven pace with pages that are each clearly worth reading is the safe way to start.

Raise the pace when the site has earned it. Signs it has: most published guides are indexed, impressions are growing week over week, and a few pages hold top-20 positions. Then move `maxPerWeek` to 7. If new pages stop getting indexed, slow down and improve existing pages instead.

Improving an existing page (a better title, a new section, a refreshed fact, more internal links) doesn't count toward the pace and is often worth more than a new page.

## What to write about

Not only "how to free up iPhone storage". The site covers what people with a full phone also search for, as long as each page has an honest route back to the app:

| Ring | Topics (`web/src/lib/topics.ts`) | Why |
| --- | --- | --- |
| Core | Free up space, Photos & screenshots, Videos, Privacy & safety | The problems the app solves. Fewer searches, most installs |
| Adjacent | Camera & formats, iCloud & backup, Sharing & transfer | Same reader, one step earlier or later: "video too large to send", "HEIC vs JPEG", "iCloud storage full". More searches, and each leads to a core guide |
| Comparisons | `/compare/*`, "best … apps", "… alternatives" | People already choosing an app. Fewest searches, highest conversion |

A typical week: two core, one or two adjacent, and a comparison every week or two. Never off-topic filler (general iPhone news, Android, unrelated how-tos): it earns nothing and dilutes what the site is about.

The tie-back rule: a page belongs if a reader who finishes it plausibly has a storage, photo, or video problem the app helps with, and the page can link to at least two core guides without forcing it.

## A run, start to finish

The skill has the detail. In short:

1. **Check the pace.** Count guides published in the last 7 days. If the week is full, improve an existing page instead.
2. **Pick one action.** With Search Console data: a query we show up for but don't answer, a page with impressions and a weak click rate, or a page at positions 5 to 20 that could be more complete. Without data yet: the best open row in the backlog.
3. **Check the search results** for the keyword: what kind of page ranks, what those pages miss, and whether a small site can compete.
4. **Write** the guide to `web/content/README.md`: answer first, built-in iPhone tools before the app, every fact traced to Apple or checked on the device.
5. **Link it in.** Two to four links out, and at least one link in from an existing guide.
6. **Build** (`npm run build` in `web/`). It must pass.
7. **Publish.** Commit to `main` and push; the host deploys. No branches or pull requests.
8. **Log it** in `log.md` and update the backlog row.

A run that can't trace a claim to a source leaves it out. A guide whose steps couldn't be confirmed is committed as `draft: true` (skipped by the build) with a note in the log, for a person to check on a real iPhone.

## Comparison articles

One page per competitor in `web/src/lib/comparisons.ts`, plus roundups ("best duplicate photo cleaners") and "alternatives to X" pages.

- Verify every competitor fact (price, subscription terms, features, privacy label) from the App Store listing or the competitor's own site during the run, and cite it. If it can't be verified, leave it out.
- Be fair: say where a competitor is better and where the built-in iOS tools are enough. Claims about our app must match what it ships.
- Competitor details go stale. Re-check and bump `updated` at least every quarter.

## Measuring

- **Search Console** (once set up): impressions, clicks, click rate, and position per page and query. Read through [gum](https://github.com/ehmo/gum) if it's installed, otherwise from the Search Console website.
- **Conversions:** the waitlist table's `source` column (page and CTA position) now; App Store campaign tokens after launch.
- Give a new page four weeks before judging it. Then: indexed? Impressions for the target keyword? If it has impressions and few clicks, rewrite the title and description. If it sits at positions 8 to 20, make it more complete and link to it from more pages.

## Setup checklist

**Done**

- [x] Domain live: `www.simpleshrink.com`, with the apex and the old vercel.app address redirecting to it.
- [x] Waitlist: site → n8n webhook → data table (see `web/.env.example`).

**To do (needs the owner's accounts)**

- [ ] In Vercel → Settings → Environment Variables: remove `NEXT_PUBLIC_SITE_URL` or set it to `https://www.simpleshrink.com`, and remove `NEXT_PUBLIC_APP_NAME` if it's set.
- [ ] Google Search Console: add `simpleshrink.com` as a Domain property (verified by a DNS TXT record), then submit `https://www.simpleshrink.com/sitemap.xml`.
- [ ] Bing Webmaster Tools: import the site from Search Console and submit the same sitemap.
- [ ] Optional, for automatic data: install gum and sign in, so runs can read Search Console themselves.
- [ ] After launch: set `NEXT_PUBLIC_APP_STORE_URL` and `NEXT_PUBLIC_APP_STORE_PROVIDER_TOKEN` so every CTA becomes an attributed App Store link.

## Running it on a schedule

The skill can be run by hand (`/seo`) or by a scheduled task whose prompt is "Run the seo skill". A schedule should fire on four days a week at different times (for example Monday 9:40, Wednesday 14:15, Friday 11:05, Saturday 16:30), not daily on the hour. The build's pace check is the backstop if a schedule misfires.

Never store credentials in the repo. It's public.
