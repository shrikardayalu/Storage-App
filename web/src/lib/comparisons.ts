// Popular iPhone storage cleaners we compare against. Each entry gets a page at
// /compare/<slug>, written in content/compare/<slug>.md. Until its article is
// written (`ready: false`) that page is a noindexed placeholder and stays out
// of the sitemap. The build fails if a ready entry has no article.
//
// Keep `knownFor` to what the app itself advertises or what reviewers widely
// report. No claims about competitors that we haven't checked.

export type Competitor = {
  slug: string;
  name: string;
  maker?: string;
  /** Official App Store artwork, served locally. Sources: public/competitors/README.md. */
  icon: string;
  /** One line on what the app is best known for. */
  knownFor: string;
  /** Short tags for the card. */
  tags: string[];
  ready: boolean;
};

export const competitors: Competitor[] = [
  {
    slug: "cleanup",
    icon: "/competitors/cleanup.jpg",
    name: "Cleanup",
    knownFor: "One of the top-grossing cleaner apps on the App Store: duplicates, similar shots, and contacts in one place.",
    tags: ["Duplicates", "Similar photos", "Contacts"],
    ready: true,
  },
  {
    slug: "clever-cleaner",
    icon: "/competitors/clever-cleaner.jpg",
    name: "Clever Cleaner",
    maker: "CleverFiles",
    knownFor: "From the makers of Disk Drill: groups similar photos and compresses Live Photos and videos, free within daily limits.",
    tags: ["Daily free limit", "Similar photos", "Compression"],
    ready: true,
  },
  {
    slug: "cleanmy-phone",
    icon: "/competitors/cleanmy-phone.jpg",
    name: "CleanMy®Phone",
    maker: "MacPaw",
    knownFor: "MacPaw's AI-sorted cleaner, the successor to Gemini Photos, from the makers of CleanMyMac.",
    tags: ["AI sorting", "Duplicates", "Subscription"],
    ready: true,
  },
  {
    slug: "cleaner-kit",
    icon: "/competitors/cleaner-kit.jpg",
    name: "Cleaner Kit",
    maker: "BPMobile",
    knownFor: "Groups duplicate and similar photos, screenshots, and videos for quick bulk review.",
    tags: ["Photo grouping", "Screenshots", "Videos"],
    ready: true,
  },
  {
    slug: "swipewipe",
    icon: "/competitors/swipewipe.jpg",
    name: "Swipewipe",
    maker: "MWM",
    knownFor: "Swipe left to delete, right to keep: a fast way to work through your camera roll month by month.",
    tags: ["Swipe to sort", "Camera roll"],
    ready: true,
  },
  {
    slug: "slidebox",
    icon: "/competitors/slidebox.jpg",
    name: "Slidebox",
    knownFor: "Swipe through photos one at a time to trash them or file them into albums.",
    tags: ["Swipe to sort", "Albums"],
    ready: true,
  },
];

export function getCompetitor(slug: string) {
  return competitors.find((c) => c.slug === slug) ?? null;
}

export const compareHref = (slug: string) => `/compare/${slug}`;
