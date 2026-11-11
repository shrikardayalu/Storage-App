// /llms.txt: a plain-Markdown map of the site for LLM crawlers and agents
// (https://llmstxt.org). Lists every guide with its one-line summary.

import { getAllCompareArticles } from "@/lib/compare-articles";
import { getAllGuides } from "@/lib/guides";
import { formatPrice, plans } from "@/lib/pricing";
import { absoluteUrl, siteConfig } from "@/lib/site";
import { topics } from "@/lib/topics";

export function GET() {
  const guides = getAllGuides();
  const lines = [
    `# ${siteConfig.name}`,
    "",
    `> ${siteConfig.description}`,
    "",
    "Every guide opens with a short direct answer, then step-by-step instructions that use the iPhone's built-in tools before mentioning the app.",
    "",
  ];

  for (const topic of topics) {
    const inTopic = guides.filter((g) => g.topic === topic.id);
    if (!inTopic.length) continue;
    lines.push(`## ${topic.name}`, "");
    for (const g of inTopic) {
      lines.push(`- [${g.title}](${absoluteUrl(`/guides/${g.slug}`)}): ${g.description}`);
    }
    lines.push("");
  }

  const comparisons = getAllCompareArticles().filter((a) => a.competitor.ready);
  if (comparisons.length) {
    lines.push("## Comparisons", "");
    for (const a of comparisons) {
      lines.push(`- [${a.title}](${absoluteUrl(`/compare/${a.competitor.slug}`)}): ${a.description}`);
    }
    lines.push("");
  }

  lines.push(
    "## About",
    "",
    `- [Pricing](${absoluteUrl("/pricing")}): Free to scan and delete. Pro starts at ${formatPrice(plans.weekly.price)} a week.`,
    `- [About ${siteConfig.name}](${absoluteUrl("/about")})`,
    `- [Privacy](${absoluteUrl("/privacy")})`,
    "",
  );

  return new Response(lines.join("\n"), {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
