// Loads Markdown guides from content/guides/, validates them, and renders them
// to HTML. Everything here runs at build time: a guide with missing fields, a
// broken internal link, or a duplicate target keyword fails the build instead
// of shipping. See content/README.md for the authoring format.

import fs from "node:fs";
import path from "node:path";
import matter from "gray-matter";
import { Marked, type Tokens } from "marked";
import { siteConfig } from "@/lib/site";
import { getTopic, topics, type TopicId } from "@/lib/topics";

const GUIDES_DIR = path.join(process.cwd(), "content", "guides");

/** Marks the spot for a mid-article call to action. */
export const CTA_MARKER = "<!-- cta -->";

/** Site routes that are not guides; internal links may point at these. */
const STATIC_ROUTES = new Set(["/", "/guides", "/about", "/privacy"]);

export type FaqItem = { q: string; a: string };

export type GuideMeta = {
  slug: string;
  title: string;
  seoTitle: string;
  description: string;
  topic: TopicId;
  primaryKeyword: string;
  published: string;
  updated: string;
  quickAnswer: string;
  illustration: string;
  related: string[];
  faq: FaqItem[];
  /** Optional CTA copy tied to this guide's problem; falls back to a generic pitch. */
  cta: { title: string; body: string } | null;
  readingMinutes: number;
};

export type TocEntry = { id: string; text: string };

export type Guide = GuideMeta & {
  /** Article HTML split at each CTA marker; render a CTA between segments. */
  segments: string[];
  toc: TocEntry[];
  quickAnswerHtml: string;
  faqHtml: { q: string; a: string }[];
};

type RawGuide = { meta: GuideMeta; body: string };

function decodeEntities(text: string) {
  return text
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function slugify(text: string) {
  return text
    .toLowerCase()
    .replace(/&[a-z]+;/g, "")
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-");
}

function toDateString(value: unknown, field: string, file: string) {
  // YAML parses unquoted dates into Date objects.
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  throw new Error(`${file}: "${field}" must be a YYYY-MM-DD date`);
}

function requireString(data: Record<string, unknown>, field: string, file: string) {
  const value = data[field];
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${file}: missing required frontmatter field "${field}"`);
  }
  return value.trim();
}

function readRawGuides(): RawGuide[] {
  if (!fs.existsSync(GUIDES_DIR)) return [];

  return fs
    .readdirSync(GUIDES_DIR)
    .filter((file) => file.endsWith(".md"))
    .map((file) => {
      // `{app}` in a guide becomes the app's current name, so a rebrand needs no content edits.
      const source = fs
        .readFileSync(path.join(GUIDES_DIR, file), "utf8")
        .replaceAll("{app}", siteConfig.name);
      const { data, content } = matter(source);
      if (data.draft === true) return null;

      const slug = file.replace(/\.md$/, "");
      if (slug !== slugify(slug)) {
        throw new Error(`${file}: file names must be lowercase-kebab-case slugs`);
      }

      const topic = requireString(data, "topic", file);
      if (!getTopic(topic)) {
        throw new Error(
          `${file}: unknown topic "${topic}". Use one of: ${topics.map((t) => t.id).join(", ")}`,
        );
      }

      const faq = (Array.isArray(data.faq) ? data.faq : []).map((item: unknown, i: number) => {
        const entry = item as Partial<FaqItem>;
        if (!entry?.q || !entry?.a) throw new Error(`${file}: faq[${i}] needs "q" and "a"`);
        return { q: String(entry.q).trim(), a: String(entry.a).trim() };
      });

      const title = requireString(data, "title", file);
      const words = content.split(/\s+/).filter(Boolean).length;

      const meta: GuideMeta = {
        slug,
        title,
        seoTitle: typeof data.seoTitle === "string" ? data.seoTitle.trim() : title,
        description: requireString(data, "description", file),
        topic: topic as TopicId,
        primaryKeyword: requireString(data, "primaryKeyword", file).toLowerCase(),
        published: toDateString(data.published, "published", file),
        updated: toDateString(data.updated ?? data.published, "updated", file),
        quickAnswer: requireString(data, "quickAnswer", file),
        illustration: typeof data.illustration === "string" ? data.illustration : "ill-phone-sparkle",
        related: Array.isArray(data.related) ? data.related.map(String) : [],
        faq,
        cta:
          typeof data.ctaTitle === "string" && typeof data.ctaBody === "string"
            ? { title: data.ctaTitle.trim(), body: data.ctaBody.trim() }
            : null,
        readingMinutes: Math.max(1, Math.round(words / 220)),
      };

      return { meta, body: content };
    })
    .filter((guide): guide is RawGuide => guide !== null);
}

/** Cross-guide checks: unique keywords, and every internal link resolves. */
function validate(guides: RawGuide[]) {
  const slugs = new Set(guides.map((g) => g.meta.slug));
  const keywords = new Map<string, string>();
  const known = (href: string) => {
    const pathname = href.split(/[?#]/)[0].replace(/\/$/, "") || "/";
    if (STATIC_ROUTES.has(pathname)) return true;
    const match = pathname.match(/^\/guides\/([a-z0-9-]+)$/);
    return Boolean(match && slugs.has(match[1]));
  };

  for (const { meta, body } of guides) {
    const file = `${meta.slug}.md`;

    const owner = keywords.get(meta.primaryKeyword);
    if (owner) {
      throw new Error(
        `${file}: primaryKeyword "${meta.primaryKeyword}" is already targeted by ${owner}.md. ` +
          "Improve that guide instead of competing with it.",
      );
    }
    keywords.set(meta.primaryKeyword, meta.slug);

    for (const related of meta.related) {
      if (!slugs.has(related)) throw new Error(`${file}: related guide "${related}" does not exist`);
      if (related === meta.slug) throw new Error(`${file}: a guide can't list itself as related`);
    }

    const sources = [body, meta.quickAnswer, ...meta.faq.map((f) => f.a)].join("\n");
    for (const [, href] of sources.matchAll(/\]\((\/[^)\s]*)\)/g)) {
      if (!known(href)) throw new Error(`${file}: broken internal link "${href}"`);
    }
  }
}

function createRenderer(toc: TocEntry[] | null) {
  const marked = new Marked({ gfm: true });
  const used = new Map<string, number>();

  marked.use({
    renderer: {
      heading({ tokens, depth }: Tokens.Heading) {
        const html = this.parser.parseInline(tokens);
        const text = decodeEntities(html.replace(/<[^>]+>/g, ""));
        let id = slugify(text);
        const count = used.get(id) ?? 0;
        used.set(id, count + 1);
        if (count) id = `${id}-${count}`;
        if (depth === 2 && toc) toc.push({ id, text });
        return `<h${depth} id="${id}">${html}</h${depth}>\n`;
      },
      link({ href, title, tokens }: Tokens.Link) {
        const text = this.parser.parseInline(tokens);
        const titleAttr = title ? ` title="${title}"` : "";
        if (/^https?:\/\//.test(href)) {
          return `<a href="${href}"${titleAttr} target="_blank" rel="noopener">${text}</a>`;
        }
        return `<a href="${href}"${titleAttr}>${text}</a>`;
      },
      table(token: Tokens.Table) {
        // Wrap tables so wide ones scroll on phones instead of the page.
        const header = token.header
          .map((cell) => `<th>${this.parser.parseInline(cell.tokens)}</th>`)
          .join("");
        const rows = token.rows
          .map(
            (row) =>
              `<tr>${row.map((cell) => `<td>${this.parser.parseInline(cell.tokens)}</td>`).join("")}</tr>`,
          )
          .join("");
        return `<div class="table-scroll"><table><thead><tr>${header}</tr></thead><tbody>${rows}</tbody></table></div>\n`;
      },
    },
  });

  return marked;
}

let cache: { raw: RawGuide[]; bySlug: Map<string, RawGuide> } | null = null;

function load() {
  if (!cache) {
    const raw = readRawGuides().sort((a, b) => b.meta.updated.localeCompare(a.meta.updated));
    validate(raw);
    cache = { raw, bySlug: new Map(raw.map((g) => [g.meta.slug, g])) };
  }
  return cache;
}

export function getAllGuides(): GuideMeta[] {
  return load().raw.map((g) => g.meta);
}

export function getGuidesByTopic(topic: TopicId): GuideMeta[] {
  return getAllGuides().filter((g) => g.topic === topic);
}

export function getGuide(slug: string): Guide | null {
  const raw = load().bySlug.get(slug);
  if (!raw) return null;

  const toc: TocEntry[] = [];
  const body = createRenderer(toc).parse(raw.body, { async: false });

  return {
    ...raw.meta,
    segments: body.split(CTA_MARKER),
    toc,
    quickAnswerHtml: markdownToHtml(raw.meta.quickAnswer),
    faqHtml: raw.meta.faq.map((f) => ({ q: f.q, a: markdownToHtml(f.a) })),
  };
}

/** Link to a guide from page code. Throws at build time if the guide doesn't exist. */
export function guideHref(slug: string) {
  if (!load().bySlug.has(slug)) throw new Error(`guideHref: no guide with slug "${slug}"`);
  return `/guides/${slug}`;
}

/** Renders a short trusted Markdown snippet (FAQ answers and the like). */
export function markdownToHtml(markdown: string) {
  return createRenderer(null).parse(markdown, { async: false });
}

/**
 * Related reading: hand-picked guides first, then the rest of the same topic,
 * then the newest guides overall, so every page links onward.
 */
export function getRelatedGuides(meta: GuideMeta, limit = 3): GuideMeta[] {
  const all = getAllGuides();
  const picked = new Map<string, GuideMeta>();
  const add = (g?: GuideMeta) => {
    if (g && g.slug !== meta.slug && picked.size < limit) picked.set(g.slug, g);
  };
  meta.related.forEach((slug) => add(all.find((g) => g.slug === slug)));
  all.filter((g) => g.topic === meta.topic).forEach(add);
  all.forEach(add);
  return [...picked.values()];
}
