import type { MetadataRoute } from "next";
import { getAllCompareArticles } from "@/lib/compare-articles";
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
    ...getAllCompareArticles()
      .filter((a) => a.competitor.ready)
      .map((a) => ({ url: absoluteUrl(`/compare/${a.competitor.slug}`), lastModified: a.updated })),
    { url: absoluteUrl("/pricing") },
    { url: absoluteUrl("/about") },
    { url: absoluteUrl("/support") },
    { url: absoluteUrl("/privacy") },
    { url: absoluteUrl("/terms") },
  ];
}
