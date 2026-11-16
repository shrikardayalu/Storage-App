// Topic clusters for the guides library. Every guide belongs to exactly one
// topic; the guides hub groups by topic so each cluster reads as a coherent
// set of pages that link to each other (topical authority).
//
// The first three are the core: problems the app solves directly. The rest are
// adjacent: things the same people search for (camera settings, iCloud,
// sharing) that lead back to the core guides. A topic with no guides yet is
// hidden everywhere, so adding one here costs nothing until it's used.

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
    id: "camera-and-formats",
    name: "Camera & formats",
    blurb: "HEIC, 4K, ProRAW and the camera settings that decide how big every new shot is.",
    illustration: "ill-beaker",
  },
  {
    id: "icloud-and-backup",
    name: "iCloud & backup",
    blurb: "What iCloud really stores, what it doesn't, and how to back up before you clear anything.",
    illustration: "ill-umbrella",
  },
  {
    id: "sharing-and-transfer",
    name: "Sharing & transfer",
    blurb: "Send big videos, move photos to a computer or drive, and switch phones without losing any.",
    illustration: "ill-empty-box",
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
