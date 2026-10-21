// Public site configuration. NEXT_PUBLIC_* values are inlined at build time,
// so each variable must be referenced directly (no dynamic lookups).

const rawUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const siteConfig = {
  name: process.env.NEXT_PUBLIC_APP_NAME || "Storage App",
  /** Canonical origin with no trailing slash. Used for canonicals, sitemap, and schema. */
  url: rawUrl.replace(/\/+$/, ""),
  tagline: "Free up iPhone storage without deleting your memories",
  description:
    "An iPhone app that frees up storage without deleting your memories: it shrinks 4K videos, trims long recordings, keeps Live Photos as stills, and re-saves bloated screenshots.",
  appStoreUrl: process.env.NEXT_PUBLIC_APP_STORE_URL || "",
  /** App Store Connect provider token, used to attribute installs to pages. */
  appStoreProviderToken: process.env.NEXT_PUBLIC_APP_STORE_PROVIDER_TOKEN || "",
  locale: "en_US",
};

export function absoluteUrl(path = "/") {
  return `${siteConfig.url}${path.startsWith("/") ? path : `/${path}`}`;
}

/**
 * App Store link tagged with an App Store Connect campaign token, so App
 * Analytics can show which page drove each install. Campaign tokens are
 * limited to 40 characters.
 */
export function appStoreLink(campaign: string) {
  if (!siteConfig.appStoreUrl) return "";
  const url = new URL(siteConfig.appStoreUrl);
  if (siteConfig.appStoreProviderToken) {
    url.searchParams.set("pt", siteConfig.appStoreProviderToken);
    url.searchParams.set("ct", campaign.slice(0, 40));
    url.searchParams.set("mt", "8");
  }
  return url.toString();
}
