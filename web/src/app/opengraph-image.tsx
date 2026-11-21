import { ImageResponse } from "next/og";
import { OgCard, ogOptions, ogSize } from "@/components/og/og-card";
import { siteConfig } from "@/lib/site";

export const alt = `${siteConfig.storeName}. ${siteConfig.tagline}`;
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    <OgCard
      eyebrow={`for iPhone · ${siteConfig.appStoreUrl ? "free on the App Store" : "launching soon"}`}
      title="Storage almost full."
      highlight="Again?"
      note="shrink it, don't delete it"
    />,
    ogOptions,
  );
}
