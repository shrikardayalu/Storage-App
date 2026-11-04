import type { MetadataRoute } from "next";
import { getAllGuides } from "@/lib/guides";
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
    { url: absoluteUrl("/pricing") },
    { url: absoluteUrl("/about") },
    { url: absoluteUrl("/support") },
    { url: absoluteUrl("/privacy") },
    { url: absoluteUrl("/terms") },
  ];
}
