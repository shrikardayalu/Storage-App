// Topic clusters for the guides library. Every guide belongs to exactly one
// topic; the guides hub groups by topic so each cluster reads as a coherent
// set of pages that link to each other (topical authority).

export type Topic = {
  id: string;
  name: string;
  blurb: string;
  illustration: string;
};

export const topics = [
  {
    id: "free-up-space",
    name: "Free up space",
    blurb: "What actually fills an iPhone, and the fastest safe ways to get room back.",
    illustration: "ill-stack-large",
  },
  {
    id: "photos-and-screenshots",
    name: "Photos & screenshots",
    blurb: "Clear duplicates, bursts, and years of screenshots without losing keepers.",
    illustration: "ill-photo",
  },
  {
    id: "videos",
    name: "Videos",
    blurb: "Videos are usually the biggest files on a phone. Shrink them or let them go.",
    illustration: "ill-video",
  },
  {
    id: "privacy-and-safety",
    name: "Privacy & safety",
    blurb: "What storage apps can and can't see, and how to tell a good one from a scam.",
    illustration: "ill-shield-check",
  },
] as const satisfies readonly Topic[];

export type TopicId = (typeof topics)[number]["id"];

export function getTopic(id: string): Topic | undefined {
  return topics.find((topic) => topic.id === id);
}
