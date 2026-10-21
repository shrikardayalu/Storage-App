# Automation

The plan for an AI-assisted SEO and content loop, modeled on how Vaultaire grew through search: find queries Google already associates with the site, publish one genuinely useful answer at a time, link it into the existing library, and measure which pages turn readers into installs. Nothing here runs yet: no scripts, scheduled jobs, API calls, or credentials. The plan is a daily Claude Code scheduled task using gum for Search Console data (see "How it runs").

## What the website already provides

The loop only writes Markdown files. Everything else is handled by `web/`:

| Need | Where it lives |
| --- | --- |
| Authoring format and quality rules | [`web/content/README.md`](../web/content/README.md) |
| Guides | `web/content/guides/*.md`, one file per URL |
| Build-time checks | `web/src/lib/guides.ts` fails the build on broken internal links, missing related guides, bad frontmatter, or a duplicate `primaryKeyword` |
| Discovery | `/sitemap.xml`, `/robots.txt` (search and AI crawlers allowed), `/guides/feed.xml`, `/llms.txt` |
| Structured data | Organization, WebSite, MobileApplication, Article, BreadcrumbList, FAQPage, CollectionPage (`web/src/lib/schema.ts`) |
| Conversion | Quick-answer box, inline CTAs at `<!-- cta -->` markers, sidebar, end-of-page CTA, mobile sticky bar |
| Attribution | Waitlist signups record the page and CTA position as `source`. After launch, App Store links carry a campaign token (`ct`) per page and position, visible in App Store Connect → App Analytics |

## The daily loop

1. **Pull data.** Last 28 days of Google Search Console queries and pages (impressions, clicks, CTR, position), via [gum](https://github.com/ehmo/gum). Until the site has impressions (the first few weeks after launch), work from a planned topic list instead.
2. **Pick one action.** Prefer, in order:
   - a query with meaningful impressions where we rank below ~10 and no page targets it (new guide),
   - a page with impressions but low CTR (rewrite `seoTitle` / `description` / `quickAnswer`),
   - a page ranking 5–20 that could be more complete (expand it, add FAQ),
   - missing internal links between related guides,
   - a comparison page (see "Comparison articles") when no data-driven action stands out.
3. **Draft on a branch.** Write or edit files in `web/content/guides/`. Run `npm run build` in `web/`. It must pass. Push a `claude/` branch and open a pull request.
4. **Human review.** A person checks every step against a real iPhone before merging. Nothing auto-publishes. Merging to `main` deploys the site.
5. **Measure.** Track each page's impressions, position, CTR, and conversions (waitlist `source` now, App Store `ct` campaign after launch), and feed results into the next run.

One focused page a day is plenty. Improving existing pages counts as much as adding new ones.

## Comparison articles

Vaultaire also grew by comparing itself with other encrypted-file apps. We do the same for iPhone storage and cleaner apps. These searches come from people already choosing an app, so they convert well. Formats:

- **"[Our app] vs [competitor]"**: one page per major cleaner/storage app.
- **"Best [category] apps for iPhone"**: roundups such as best duplicate photo cleaners or best video compressors, with our app included and ranked honestly.
- **"[Competitor] alternatives"**: for people unhappy with a specific app (subscriptions, ads, privacy).

Rules for every comparison:

- Verify every competitor fact (price, subscription terms, features, privacy policy, what data leaves the phone) from the App Store listing or the competitor's own site during the run, and cite it. If it can't be verified, leave it out.
- Put a "last checked" date on the page; competitor details go stale, so refresh comparisons regularly.
- Be fair: say where a competitor is better or where the built-in iOS tools are enough. Claims about our app must match what it actually ships.
- Use a comparison table plus a short "who should pick which" section, and a `<!-- cta -->` after the verdict.
- Before launch, keep the topic list of competitors in `automation/` and add one comparison a week alongside the regular guides.

## How it runs

The loop runs as a [Claude Code scheduled task](https://code.claude.com/docs/en/routines) (formerly "routines") in Anthropic's cloud, so no laptop needs to be on and no API credits are used. Runs draw from the Claude subscription's normal usage; there is no separate per-day run cap, only hourly limits far above one or two runs a day. No n8n or other orchestrator is needed: the scheduled task provides the schedule, and GitHub is the publish step because the site reads guides straight from the repo.

```text
6:07 am daily scheduled task   (avoid :00, on-the-hour runs can start late)
  ├─ clones shrikardayalu/Storage-App
  ├─ setup script installs gum (cached between runs)
  ├─ gum reads the last 28 days of Search Console data
  ├─ Claude picks ONE action and writes/edits web/content/guides/*.md
  ├─ npm run build in web/ (the validation in guides.ts is the safety net)
  └─ pushes a claude/ branch and opens a pull request
Review on a phone → merge → host deploys main
```

Notes:

- **Auth.** gum's default OAuth login opens a browser and stores the token in the OS keychain, which a cloud run doesn't have. Use a Google service account with read access to the Search Console property, and give the run its JSON key through the cloud environment (use a private environment; its variables are visible to anyone who uses it).
- **Network.** The default cloud environment only allows an allowlist of domains. If gum's calls fail with `403 host_not_allowed`, add `*.googleapis.com` and `oauth2.googleapis.com` (and gum's release download host, for the setup script) under the environment's network access.
- **Prompt.** The scheduled task's prompt is the agent instruction below, plus: "Use gum to fetch Search Console data. Open a pull request with the change and a one-paragraph summary of why this action was picked."
- **Fallback.** A Desktop scheduled task on a local machine also works (gum's browser login works there) but only runs while that machine is on.

## Agent instruction (starting point)

```text
You are the SEO and answer-engine agent for an iPhone storage utility.

Inputs: the last 28 days of Google Search Console data, and the guides in
web/content/guides/ (read web/content/README.md first; follow it exactly).

Recommend and prepare ONE action for today: a new guide, an improvement to an
existing guide, new internal links, or a comparison page (our app vs a
competitor, a "best apps" roundup, or "alternatives to X"). For a new guide include a quickAnswer
that fully answers the query, verified step-by-step instructions using built-in
iOS tools first, a table or FAQ where it helps, 2–4 internal links out and at
least one link in from an existing guide, a <!-- cta --> where the app is
genuinely relevant, and a one-line measurement plan. For a comparison, verify
every competitor fact from its App Store listing or website during this run,
cite it, add a "last checked" date, and say honestly where a competitor or
the built-in iOS tools are the better choice.

Never invent statistics, test results, app capabilities, or competitor facts.
Never claim any app can clear System Data or other apps' caches. Never
duplicate an existing primaryKeyword. Run `npm run build` in web/ and fix any
error. Leave the change on a branch for human review.
```

## Setup checklist (when we build it)

**Search Console**

- [ ] Set `NEXT_PUBLIC_SITE_URL` to the production domain and deploy the site.
- [ ] Add the domain as a property in Google Search Console and verify it.
- [ ] Submit `https://<domain>/sitemap.xml` in Search Console (and Bing Webmaster Tools).
- [ ] In Google Cloud: create a project, enable the Search Console API, create a service account, and download its JSON key.
- [ ] In Search Console → Settings → Users and permissions, add the service account's email with Restricted (read-only) access.

**Scheduled task**

- [ ] Connect GitHub to claude.ai so cloud runs can clone this repo and open pull requests.
- [ ] Create a private cloud environment: setup script installs gum and runs `npm ci` in `web/`; add the service account key; allow `*.googleapis.com` if needed.
- [ ] At claude.ai/code/routines: new scheduled task, daily at 6:07 am, this repo, that environment, the prompt from "How it runs". Remove connectors it doesn't need.
- [ ] Click **Run now** once and read the transcript to confirm gum returned data and a pull request opened.

**Other**

- [ ] Point `WAITLIST_WEBHOOK_URL` at an email tool or n8n webhook that stores `{ email, source, joinedAt }`.
- [ ] After launch: set `NEXT_PUBLIC_APP_STORE_URL` and `NEXT_PUBLIC_APP_STORE_PROVIDER_TOKEN` so every CTA becomes an attributed App Store link.

## Guidelines

- Keep this independent of the website's runtime. It only produces content files and reports.
- Store credentials in the scheduled task's private cloud environment or local, Git-ignored env files (e.g. `automation/.env`), never in code.
