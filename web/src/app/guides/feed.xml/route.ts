// RSS feed of guides, so feed readers and aggregators pick up new pages fast.

import { getAllGuides } from "@/lib/guides";
import { absoluteUrl, siteConfig } from "@/lib/site";

const escape = (text: string) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function GET() {
  const guides = getAllGuides();
  const items = guides
    .map((g) => {
      const url = absoluteUrl(`/guides/${g.slug}`);
      return `    <item>
      <title>${escape(g.title)}</title>
      <link>${url}</link>
      <guid isPermaLink="true">${url}</guid>
      <description>${escape(g.description)}</description>
      <pubDate>${new Date(`${g.published}T12:00:00Z`).toUTCString()}</pubDate>
    </item>`;
    })
    .join("\n");

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${escape(`${siteConfig.name} Guides`)}</title>
    <link>${absoluteUrl("/guides")}</link>
    <atom:link href="${absoluteUrl("/guides/feed.xml")}" rel="self" type="application/rss+xml" />
    <description>${escape("Practical, accurate guides to freeing up iPhone storage.")}</description>
    <language>en</language>
${items}
  </channel>
</rss>
`;

  return new Response(xml, { headers: { "Content-Type": "application/rss+xml; charset=utf-8" } });
}
