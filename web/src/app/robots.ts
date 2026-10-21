import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/site";

// Answer engines are named explicitly so it's clear they're welcome: being
// cited in AI answers is a goal, not a leak.
const ANSWER_ENGINE_BOTS = [
  "GPTBot",
  "OAI-SearchBot",
  "ChatGPT-User",
  "ClaudeBot",
  "Claude-SearchBot",
  "PerplexityBot",
  "Google-Extended",
  "Applebot-Extended",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/" },
      { userAgent: ANSWER_ENGINE_BOTS, allow: "/" },
    ],
    sitemap: absoluteUrl("/sitemap.xml"),
  };
}
