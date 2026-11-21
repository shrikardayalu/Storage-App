import { ImageResponse } from "next/og";
import { OgCard, ogOptions, ogSize } from "@/components/og/og-card";

export const alt = "Plain-English guides to freeing up iPhone storage";
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    <OgCard
      eyebrow="plain-English guides"
      title="Get your iPhone storage"
      highlight="back."
      note="no fluff, no scare tactics"
      art="ill-stack-large"
      footer="simpleshrink.com/guides"
    />,
    ogOptions,
  );
}
