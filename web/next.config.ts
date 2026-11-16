import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  cacheComponents: true,
  partialPrefetching: true,
  // The old address keeps working but hands everything to the real domain,
  // so search engines only ever index one copy of each page.
  async redirects() {
    return [
      {
        source: "/:path*",
        has: [{ type: "host", value: "simpleshrink.vercel.app" }],
        destination: "https://www.simpleshrink.com/:path*",
        permanent: true,
      },
    ];
  },
  turbopack: {
    // web/ is a standalone app (no workspaces); pin the root so lockfiles
    // in parent folders are never picked up.
    root: path.join(__dirname),
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
