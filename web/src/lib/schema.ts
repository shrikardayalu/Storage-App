// schema.org builders. Entities share stable @ids so Google and answer
// engines can join the Organization, WebSite, app, and articles into one graph.

import type { CompareArticle } from "@/lib/compare-articles";
import type { FaqItem, GuideMeta } from "@/lib/guides";
import { absoluteUrl, siteConfig } from "@/lib/site";

const ORG_ID = absoluteUrl("/#organization");
const SITE_ID = absoluteUrl("/#website");
const APP_ID = absoluteUrl("/#app");

const stripMarkdown = (text: string) =>
  text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_`]/g, "")
    .trim();

export function organizationSchema() {
  return {
    "@type": "Organization",
    "@id": ORG_ID,
    name: siteConfig.name,
    url: absoluteUrl("/"),
    logo: absoluteUrl("/logo.png"),
  };
}

export function websiteSchema() {
  return {
    "@type": "WebSite",
    "@id": SITE_ID,
    name: siteConfig.name,
    url: absoluteUrl("/"),
    publisher: { "@id": ORG_ID },
    inLanguage: "en",
  };
}

export function appSchema() {
  return {
    "@type": "MobileApplication",
    "@id": APP_ID,
    name: siteConfig.name,
    description: siteConfig.description,
    operatingSystem: "iOS 17 or later",
    applicationCategory: "UtilitiesApplication",
    publisher: { "@id": ORG_ID },
    ...(siteConfig.appStoreUrl
      ? {
          downloadUrl: siteConfig.appStoreUrl,
          offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        }
      : {}),
  };
}

export function faqSchema(items: FaqItem[]) {
  return {
    "@type": "FAQPage",
    mainEntity: items.map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: stripMarkdown(item.a) },
    })),
  };
}

export function breadcrumbSchema(crumbs: { name: string; path: string }[]) {
  return {
    "@type": "BreadcrumbList",
    itemListElement: crumbs.map((crumb, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: crumb.name,
      item: absoluteUrl(crumb.path),
    })),
  };
}

type ArticleFields = {
  path: string;
  title: string;
  description: string;
  summary: string;
  published: string;
  updated: string;
  keyword: string;
};

function article(fields: ArticleFields) {
  const url = absoluteUrl(fields.path);
  return {
    "@type": "Article",
    "@id": `${url}#article`,
    headline: fields.title,
    description: fields.description,
    abstract: stripMarkdown(fields.summary),
    url,
    mainEntityOfPage: url,
    image: absoluteUrl(`${fields.path}/opengraph-image`),
    datePublished: fields.published,
    dateModified: fields.updated,
    inLanguage: "en",
    keywords: fields.keyword,
    author: { "@id": ORG_ID },
    publisher: { "@id": ORG_ID },
    isPartOf: { "@id": SITE_ID },
    about: { "@id": APP_ID },
  };
}

export function articleSchema(guide: GuideMeta) {
  return article({
    path: `/guides/${guide.slug}`,
    title: guide.title,
    description: guide.description,
    summary: guide.quickAnswer,
    published: guide.published,
    updated: guide.updated,
    keyword: guide.primaryKeyword,
  });
}

export function compareSchema(a: CompareArticle) {
  return {
    ...article({
      path: `/compare/${a.competitor.slug}`,
      title: a.title,
      description: a.description,
      summary: a.verdict,
      published: a.published,
      updated: a.updated,
      keyword: a.primaryKeyword,
    }),
    mentions: { "@type": "MobileApplication", name: a.competitor.name, operatingSystem: "iOS" },
  };
}

/** Wraps nodes in one @graph document. */
export function graph(...nodes: object[]) {
  return { "@context": "https://schema.org", "@graph": nodes };
}
