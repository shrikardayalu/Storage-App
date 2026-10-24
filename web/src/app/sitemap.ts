import type { MetadataRoute } from "next";
import { getAllGuides } from "@/lib/guides";
import { pricingLive } from "@/lib/pricing";
import { absoluteUrl } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const guides = getAllGuides();
  const newest = guides[0]?.updated;

  return [
    { url: absoluteUrl("/"), lastModified: newest },
    { url: absoluteUrl("/guides"), lastModified: newest },
    ...guides.map((guide) => ({
      url: absoluteUrl(`/guides/${guide.slug}`),
      lastModified: guide.updated,
    })),
    ...(pricingLive ? [{ url: absoluteUrl("/pricing") }] : []),
    { url: absoluteUrl("/about") },
    { url: absoluteUrl("/privacy") },
  ];
}
