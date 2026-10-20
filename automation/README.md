# Automation

Reserved for a future AI-assisted SEO and content workflow. Nothing is implemented yet: no scripts, scheduled jobs, API calls, or credentials.

## Intended responsibilities

- **Keyword research** — discover and prioritize search topics related to iPhone storage.
- **Google Search Console** — pull search performance data for the marketing site.
- **Article drafting** — generate first drafts with AI assistance.
- **Review and approval** — every draft is reviewed by a person before publishing.
- **Publishing** — write approved Markdown/MDX files to `web/content/blog/`, which the Next.js site will render.
- **Performance tracking** — monitor rankings and traffic for published articles.

## Guidelines for when this is built

- Keep it independent of the website's runtime; it should only produce content files and reports.
- Store credentials in local, Git-ignored env files (e.g. `automation/.env`), never in code.
