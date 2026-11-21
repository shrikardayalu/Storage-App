import { ImageResponse } from "next/og";
import { OgCard, ogOptions, ogSize } from "@/components/og/og-card";
import { getAllGuides, getGuide } from "@/lib/guides";
import { siteConfig } from "@/lib/site";
import { getTopic } from "@/lib/topics";

export const alt = "Guide cover";
export const size = ogSize;
export const contentType = "image/png";

export function generateStaticParams() {
  return getAllGuides().map((guide) => ({ slug: guide.slug }));
}

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const guide = getGuide(slug);
  const topic = getTopic(guide?.topic ?? "");
  return new ImageResponse(
    <OgCard
      eyebrow={topic ? `guide · ${topic.name.toLowerCase()}` : "iPhone storage guide"}
      title={guide?.title ?? siteConfig.name}
      note={`${guide?.readingMinutes ?? 5} min read, no fluff`}
      art={topic?.illustration}
      footer={`simpleshrink.com/guides${guide?.updated ? ` · updated ${guide.updated}` : ""}`}
    />,
    ogOptions,
  );
}
