// Loads the comparison articles from content/compare/<slug>.md. Like guides,
// everything runs at build time and a bad article fails the build: unknown
// competitor, missing fields, broken internal links, a ready competitor with
// no article, or a source that isn't a full URL. See content/README.md.

import fs from "node:fs";
import path from "node:path";
import matter from "gray-matter";
import { competitors, getCompetitor, type Competitor } from "@/lib/comparisons";
import { createComparisonTableRenderer } from "@/lib/comparison-table";
import { isKnownRoute, markdownToHtml, renderArticle, type FaqItem, type TocEntry } from "@/lib/guides";
import { formatPrice, plans } from "@/lib/pricing";
import { siteConfig } from "@/lib/site";

const COMPARE_DIR = path.join(process.cwd(), "content", "compare");

export type Source = { label: string; url: string };

export type CompareArticle = {
  competitor: Competitor;
  title: string;
  seoTitle: string;
  description: string;
  primaryKeyword: string;
  published: string;
  updated: string;
  verdictHtml: string;
  verdict: string;
  cta: { title: string; body: string };
  faq: FaqItem[];
  faqHtml: FaqItem[];
  sources: Source[];
  segments: string[];
  toc: TocEntry[];
  readingMinutes: number;
};

/** Placeholders an article can use so names and prices never go stale. */
function fillPlaceholders(source: string) {
  return source
    .replaceAll("{app}", siteConfig.name)
    .replaceAll("{weekly}", formatPrice(plans.weekly.price))
    .replaceAll("{annual}", formatPrice(plans.annual.price));
}

function toDateString(value: unknown, field: string, file: string) {
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

function loadAll(): Map<string, CompareArticle> {
  const articles = new Map<string, CompareArticle>();
  const files = fs.existsSync(COMPARE_DIR) ? fs.readdirSync(COMPARE_DIR).filter((f) => f.endsWith(".md")) : [];

  for (const file of files) {
    const slug = file.replace(/\.md$/, "");
    const competitor = getCompetitor(slug);
    if (!competitor) throw new Error(`${file}: no competitor with slug "${slug}" in src/lib/comparisons.ts`);

    const { data, content } = matter(fillPlaceholders(fs.readFileSync(path.join(COMPARE_DIR, file), "utf8")));
    if (data.draft === true) continue;

    const faq = (Array.isArray(data.faq) ? data.faq : []).map((item: unknown, i: number) => {
      const entry = item as Partial<FaqItem>;
      if (!entry?.q || !entry?.a) throw new Error(`${file}: faq[${i}] needs "q" and "a"`);
      return { q: String(entry.q).trim(), a: String(entry.a).trim() };
    });

    const sources = (Array.isArray(data.sources) ? data.sources : []).map((item: unknown, i: number) => {
      const entry = item as Partial<Source>;
      if (!entry?.label || !entry?.url || !/^https:\/\//.test(entry.url)) {
        throw new Error(`${file}: sources[${i}] needs a "label" and an https "url"`);
      }
      return { label: String(entry.label).trim(), url: String(entry.url).trim() };
    });
    if (!sources.length) throw new Error(`${file}: list the sources every competitor fact was checked against`);

    const verdict = requireString(data, "verdict", file);
    for (const [, href] of [content, verdict, ...faq.map((f) => f.a)].join("\n").matchAll(/\]\((\/[^)\s]*)\)/g)) {
      if (!isKnownRoute(href)) throw new Error(`${file}: broken internal link "${href}"`);
    }

    const title = requireString(data, "title", file);
    articles.set(slug, {
      competitor,
      title,
      seoTitle: typeof data.seoTitle === "string" ? data.seoTitle.trim() : title,
      description: requireString(data, "description", file),
      primaryKeyword: requireString(data, "primaryKeyword", file).toLowerCase(),
      published: toDateString(data.published, "published", file),
      updated: toDateString(data.updated ?? data.published, "updated", file),
      verdict,
      verdictHtml: markdownToHtml(verdict),
      cta: { title: requireString(data, "ctaTitle", file), body: requireString(data, "ctaBody", file) },
      faq,
      faqHtml: faq.map((f) => ({ q: f.q, a: markdownToHtml(f.a) })),
      sources,
      ...renderArticle(content, { renderTable: createComparisonTableRenderer(competitor) }),
      readingMinutes: Math.max(1, Math.round(content.split(/\s+/).filter(Boolean).length / 220)),
    });
  }

  for (const c of competitors) {
    if (c.ready && !articles.has(c.slug)) {
      throw new Error(`comparisons.ts: "${c.slug}" is ready but content/compare/${c.slug}.md is missing`);
    }
  }
  return articles;
}

let cache: Map<string, CompareArticle> | null = null;

export function getCompareArticle(slug: string): CompareArticle | null {
  cache ??= loadAll();
  return cache.get(slug) ?? null;
}

export function getAllCompareArticles(): CompareArticle[] {
  cache ??= loadAll();
  return [...cache.values()];
}
