import { ImageResponse } from "next/og";
import { OgCard, ogSize } from "@/components/og/og-card";
import { siteConfig } from "@/lib/site";

export const alt = `${siteConfig.name}: ${siteConfig.tagline}`;
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    <OgCard eyebrow={`${siteConfig.name} for iPhone`} title="Storage almost full. Again?" footer="Shrink the videos, compress the long ones, turn Live Photos into stills, and more." />,
    size,
  );
}
