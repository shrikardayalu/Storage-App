import { ImageResponse } from "next/og";
import { OgCard, ogSize } from "@/components/og/og-card";
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
  return new ImageResponse(
    <OgCard
      eyebrow={`${siteConfig.name} Guides · ${getTopic(guide?.topic ?? "")?.name ?? ""}`}
      title={guide?.title ?? siteConfig.name}
      footer={`${guide?.readingMinutes ?? 5} min read · Updated ${guide?.updated ?? ""}`}
    />,
    size,
  );
}
