// Popular iPhone storage cleaners we compare against. Each entry gets a page at
// /compare/<slug>. Until its article is written (`ready: false`) that page is a
// noindexed placeholder and stays out of the sitemap.
//
// Keep `knownFor` to what the app itself advertises or what reviewers widely
// report. No claims about competitors that we haven't checked.

export type Competitor = {
  slug: string;
  name: string;
  maker?: string;
  /** One line on what the app is best known for. */
  knownFor: string;
  /** Short tags for the card. */
  tags: string[];
  ready: boolean;
};

export const competitors: Competitor[] = [
  {
    slug: "cleanup",
    name: "Cleanup",
    knownFor: "One of the top-grossing cleaner apps on the App Store: duplicates, similar shots, and contacts in one place.",
    tags: ["Duplicates", "Similar photos", "Contacts"],
    ready: false,
  },
  {
    slug: "clever-cleaner",
    name: "Clever Cleaner",
    maker: "CleverFiles",
    knownFor: "A free cleaner that groups similar photos and offers Live Photo and video compression.",
    tags: ["Free", "Similar photos", "Compression"],
    ready: false,
  },
  {
    slug: "cleanmy-phone",
    name: "CleanMy®Phone",
    maker: "MacPaw",
    knownFor: "MacPaw's AI-sorted cleaner, the successor to Gemini Photos, from the makers of CleanMyMac.",
    tags: ["AI sorting", "Duplicates", "Subscription"],
    ready: false,
  },
  {
    slug: "cleaner-kit",
    name: "Cleaner Kit",
    knownFor: "Groups duplicate and similar photos, screenshots, and videos for quick bulk review.",
    tags: ["Photo grouping", "Screenshots", "Videos"],
    ready: false,
  },
  {
    slug: "swipewipe",
    name: "Swipewipe",
    knownFor: "Swipe left to delete, right to keep: a fast way to work through your camera roll month by month.",
    tags: ["Swipe to sort", "Camera roll"],
    ready: false,
  },
  {
    slug: "slidebox",
    name: "Slidebox",
    knownFor: "Swipe through photos one at a time to trash them or file them into albums.",
    tags: ["Swipe to sort", "Albums"],
    ready: false,
  },
];

export function getCompetitor(slug: string) {
  return competitors.find((c) => c.slug === slug) ?? null;
}

export const compareHref = (slug: string) => `/compare/${slug}`;
