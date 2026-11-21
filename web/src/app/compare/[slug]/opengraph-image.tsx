import { ImageResponse } from "next/og";
import { OgCard, ogOptions, ogSize } from "@/components/og/og-card";
import { getCompareArticle } from "@/lib/compare-articles";
import { competitors, getCompetitor } from "@/lib/comparisons";
import { siteConfig } from "@/lib/site";

export const alt = "Comparison cover";
export const size = ogSize;
export const contentType = "image/png";

export function generateStaticParams() {
  return competitors.map((c) => ({ slug: c.slug }));
}

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const competitor = getCompetitor(slug);
  const article = competitor?.ready ? getCompareArticle(slug) : null;
  return new ImageResponse(
    <OgCard
      eyebrow="the honest comparison"
      title={siteConfig.name}
      highlight={`vs ${competitor?.name ?? "the rest"}`}
      note={article ? "facts checked, no spin" : "comparison coming soon"}
      art="ill-shield-check"
      footer={article ? `simpleshrink.com/compare · checked ${article.updated}` : "simpleshrink.com/compare"}
    />,
    ogOptions,
  );
}
