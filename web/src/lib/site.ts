// Public site configuration. NEXT_PUBLIC_* values are inlined at build time,
// so each variable must be referenced directly (no dynamic lookups).

export const siteConfig = {
  name: process.env.NEXT_PUBLIC_APP_NAME || "Storage App",
  description:
    "An iPhone utility that helps you find unnecessary photos, screenshots, and large videos, then remove or compress them to free up storage.",
  appStoreUrl: process.env.NEXT_PUBLIC_APP_STORE_URL || "",
};
