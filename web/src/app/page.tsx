import type { ReactNode } from "react";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { siteConfig } from "@/lib/site";

type Feature = {
  title: string;
  description: string;
  icon: ReactNode;
};

const iconProps = {
  width: 20,
  height: 20,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.75,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

const features: Feature[] = [
  {
    title: "Find large files",
    description:
      "See which videos and photos take up the most space, sorted by size.",
    icon: (
      <svg {...iconProps}>
        <circle cx="11" cy="11" r="7" />
        <path d="m20 20-3.5-3.5" />
      </svg>
    ),
  },
  {
    title: "Review clutter",
    description:
      "Go through old screenshots and unwanted photos in one place, and keep only what you want.",
    icon: (
      <svg {...iconProps}>
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <path d="m8 12 3 3 5-6" />
      </svg>
    ),
  },
  {
    title: "Compress supported media",
    description:
      "Shrink supported videos to a smaller file size instead of deleting them.",
    icon: (
      <svg {...iconProps}>
        <path d="M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7" />
      </svg>
    ),
  },
];

export default function Home() {
  return (
    <>
      <SiteHeader />

      <main className="flex-1">
        <section className="mx-auto max-w-5xl px-5 pt-16 pb-20 sm:px-8 sm:pt-24 sm:pb-28">
          <p className="text-sm font-medium text-teal-700">For iPhone</p>
          <h1 className="mt-3 max-w-2xl text-4xl font-semibold tracking-tight text-balance text-slate-900 sm:text-5xl">
            Reclaim storage on your iPhone without losing what matters.
          </h1>
          <p className="mt-5 max-w-xl text-lg leading-relaxed text-pretty text-slate-600">
            {siteConfig.name} finds the photos, screenshots, and large videos
            filling up your phone. You decide what to remove and what to
            compress.
          </p>

          <div
            role="status"
            className="mt-10 flex max-w-xl items-start gap-3 rounded-2xl border border-teal-100 bg-teal-50/60 p-4 sm:items-center"
          >
            <span
              aria-hidden="true"
              className="mt-1.5 size-2 shrink-0 rounded-full bg-teal-500 sm:mt-0"
            />
            <p className="text-sm text-slate-700">
              <span className="font-semibold text-slate-900">Coming soon.</span>{" "}
              {siteConfig.appStoreUrl ? (
                <a
                  href={siteConfig.appStoreUrl}
                  className="font-medium text-teal-700 underline underline-offset-4 hover:text-teal-800"
                >
                  View on the App Store
                </a>
              ) : (
                "The app is in development and not yet available on the App Store."
              )}
            </p>
          </div>
        </section>

        <section
          aria-labelledby="features-heading"
          className="border-t border-slate-200/70 bg-slate-50"
        >
          <div className="mx-auto max-w-5xl px-5 py-16 sm:px-8 sm:py-20">
            <h2
              id="features-heading"
              className="text-2xl font-semibold tracking-tight text-slate-900"
            >
              What it does
            </h2>
            <ul className="mt-8 grid gap-4 sm:grid-cols-3">
              {features.map((feature) => (
                <li
                  key={feature.title}
                  className="rounded-2xl border border-slate-200 bg-white p-6"
                >
                  <div className="grid size-10 place-items-center rounded-xl bg-teal-50 text-teal-700">
                    {feature.icon}
                  </div>
                  <h3 className="mt-4 font-semibold text-slate-900">
                    {feature.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-slate-600">
                    {feature.description}
                  </p>
                </li>
              ))}
            </ul>
          </div>
        </section>
      </main>

      <SiteFooter />
    </>
  );
}
