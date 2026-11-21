import { ImageResponse } from "next/og";
import { OgCard, ogOptions, ogSize } from "@/components/og/og-card";

export const alt = "iPhone storage cleaner apps, compared honestly";
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    <OgCard
      eyebrow="the honest comparison"
      title="Which iPhone cleaner"
      highlight="is worth it?"
      note="six apps, facts checked"
      art="ill-shield-check"
      footer="simpleshrink.com/compare"
    />,
    ogOptions,
  );
}
