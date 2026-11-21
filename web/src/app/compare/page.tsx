import type { CSSProperties } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { AppCta } from "@/components/app-cta";
import { CompareCard } from "@/components/compare-card";
import { FaqList } from "@/components/faq-list";
import { Illustration, Strike } from "@/components/ink";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { getAllCompareArticles } from "@/lib/compare-articles";
import { compareHref, competitors } from "@/lib/comparisons";
import { guideHref, markdownToHtml } from "@/lib/guides";
import { formatPrice, plans } from "@/lib/pricing";
import { breadcrumbSchema, faqSchema, graph } from "@/lib/schema";
import { absoluteUrl, siteConfig } from "@/lib/site";

const name = siteConfig.name;

const title = "Best iPhone Storage Cleaner Apps";
const description =
  "Photos already finds duplicates and screenshots. See when that's enough, then how six iPhone storage cleaners compare.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/compare" },
  openGraph: { type: "website", siteName: name, title: `${title} | ${name}`, description, url: "/compare" },
  twitter: { card: "summary_large_image", title: `${title} | ${name}`, description },
};

const formatDate = (date: string) =>
  new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  });

const builtIn = [
  {
    href: guideHref("delete-duplicate-photos-iphone"),
    title: "Merge duplicates",
    body: "Photos has a Duplicates album on iOS 16 and later. Merge keeps one copy and moves the rest to Recently Deleted.",
    link: "How to delete duplicate photos",
  },
  {
    href: guideHref("delete-all-screenshots-iphone"),
    title: "Clear screenshots",
    body: "Screenshots sit in their own album, so you can remove the pile and keep the few you still need.",
    link: "How to delete screenshots",
  },
  {
    href: guideHref("empty-recently-deleted-iphone"),
    title: "Empty Recently Deleted",
    body: "Deleted photos keep using space for about 30 days. The storage comes back when you empty the album.",
    link: "How to empty Recently Deleted",
  },
];

const jobs = [
  { href: compareHref("slidebox"), label: "Filing photos into albums by hand", name: "Slidebox" },
  { href: compareHref("swipewipe"), label: "Swiping through your whole camera roll", name: "Swipewipe" },
  { href: compareHref("cleanup"), label: "Contacts, email, and photos in one app", name: "Cleanup" },
  { href: compareHref("cleaner-kit"), label: "Duplicates, screenshots, and videos in bulk", name: "Cleaner Kit" },
  { href: compareHref("clever-cleaner"), label: "Compression, free up to a daily limit", name: "Clever Cleaner" },
  { href: compareHref("cleanmy-phone"), label: "An AI-sorted photo library", name: "CleanMy®Phone" },
];

const faq = [
  {
    q: "What is the best iPhone storage cleaner?",
    a: "For duplicates and screenshots, Photos. It already does both. A separate app is the better cleaner when the space is in videos and Live Photos you want to keep, because Photos can only delete those.",
  },
  {
    q: "Do I need a cleaner app at all?",
    a: `Often, no. Merge duplicates, clear the Screenshots album, and empty Recently Deleted before you install anything. [Are iPhone cleaner apps safe?](${guideHref("are-iphone-cleaner-apps-safe")}) covers what they can and can't do.`,
  },
  {
    q: "Can any cleaner remove System Data?",
    a: `No. iOS keeps every app sandboxed, so none of them can clear System Data, wipe another app's cache, or boost RAM. [Why iPhone System Data gets so large](${guideHref("iphone-system-data-too-large")}) explains what actually shrinks it.`,
  },
];

export default function CompareIndexPage() {
  const ready = competitors.filter((c) => c.ready);
  const checked = getAllCompareArticles()
    .filter((a) => a.competitor.ready)
    .map((a) => a.updated)
    .sort()
    .at(-1);
  const faqHtml = faq.map((item) => ({ q: item.q, a: markdownToHtml(item.a) }));

  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1 overflow-x-clip">
        <header className="mx-auto max-w-6xl px-5 pt-10 sm:px-8 sm:pt-14">
          <nav aria-label="Breadcrumb" className="text-sm text-ink-faint">
            <ol className="flex flex-wrap items-center gap-1.5">
              <li>
                <Link href="/" className="hover:text-ink">
                  Home
                </Link>
              </li>
              <li aria-hidden="true">/</li>
              <li>Compare</li>
            </ol>
          </nav>

          <div className="mt-8 grid items-end gap-8 lg:grid-cols-[1fr_auto]">
            <div className="max-w-3xl">
              <p className="eyebrow">comparisons</p>
              <h1 className="mt-3 font-display text-[clamp(2.2rem,1.2rem+4vw,4.2rem)] leading-[0.98] font-extrabold text-balance">
                Best iPhone storage cleaners, starting with Photos.
              </h1>
              <p className="mt-5 text-lg leading-relaxed text-pretty text-ink-soft sm:text-xl">
                The best iPhone storage cleaner for duplicates and screenshots is already installed. Another app
                earns its place when the space is in videos and Live Photos you want to keep, which Photos can
                only delete.
              </p>
              <p className="mt-6 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-ink-faint">
                <span>
                  By the{" "}
                  <Link href="/about" className="font-semibold text-ink-soft hover:text-ink">
                    {name} team
                  </Link>
                </span>
                {checked && (
                  <>
                    <span aria-hidden="true">·</span>
                    <span>
                      Comparisons checked <time dateTime={checked}>{formatDate(checked)}</time>
                    </span>
                  </>
                )}
              </p>
            </div>
            <Illustration name="ill-beaker" size={150} priority className="hidden -rotate-6 lg:block" />
          </div>
        </header>

        <section className="mx-auto max-w-6xl px-5 py-20 sm:px-8" aria-labelledby="builtin-heading">
          <div className="max-w-2xl">
            <p className="eyebrow">start here</p>
            <h2 id="builtin-heading" className="mt-3 font-display text-[clamp(2rem,4vw,3.2rem)] leading-[1] font-extrabold">
              Use what&apos;s already on your iPhone.
            </h2>
            <p className="mt-5 text-lg leading-relaxed text-ink-soft">
              These three recover real space, cost nothing, and don&apos;t require an account.
            </p>
          </div>
          <div className="mt-12 grid gap-6 md:grid-cols-3">
            {builtIn.map((item, i) => (
              <article
                key={item.href}
                className="sticker flex flex-col p-7"
                data-reveal
                style={{ "--reveal-delay": i * 90 } as CSSProperties}
              >
                <h3 className="font-display text-2xl font-bold">{item.title}</h3>
                <p className="mt-3 leading-relaxed text-ink-soft">{item.body}</p>
                <Link
                  href={item.href}
                  className="mt-auto self-start pt-6 text-sm font-semibold underline decoration-mint decoration-[3px] underline-offset-4 hover:decoration-ink"
                >
                  {item.link} <span aria-hidden="true">→</span>
                </Link>
              </article>
            ))}
          </div>
        </section>

        <section className="border-y-2 border-ink bg-surface">
          <div className="mx-auto grid max-w-6xl items-center gap-10 px-5 py-16 sm:px-8 lg:grid-cols-[1.2fr_0.8fr]">
            <div>
              <p className="eyebrow">the limit</p>
              <h2 className="mt-3 font-display text-[clamp(2rem,4vw,3.2rem)] leading-[1] font-extrabold">
                No cleaner can touch System Data.
              </h2>
              <p className="mt-5 max-w-xl text-lg leading-relaxed text-ink-soft">
                iOS keeps every app in a sandbox. None of the apps below can wipe System Data, clear another
                app&apos;s cache, or boost RAM. Be wary of any listing that says it can.
              </p>
              <Link
                href={guideHref("are-iphone-cleaner-apps-safe")}
                className="mt-6 inline-flex items-center gap-2 font-semibold underline decoration-mint decoration-[3px] underline-offset-4 hover:decoration-ink"
              >
                Are iPhone cleaner apps safe? <span aria-hidden="true">→</span>
              </Link>
            </div>
            <ul className="sticker space-y-4 p-6 font-display text-lg font-semibold">
              {["Boost your RAM", "Remove viruses", "Wipe System Data", "Clear other apps' caches"].map((claim) => (
                <li key={claim} className="relative w-fit text-ink-faint">
                  {claim}
                  <Strike className="absolute top-1/2 -left-1 h-3 w-[110%] -translate-y-1/2" />
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-5 py-20 sm:px-8" aria-labelledby="apps-heading">
          <div className="max-w-2xl">
            <p className="eyebrow">then, an app</p>
            <h2 id="apps-heading" className="mt-3 font-display text-[clamp(2rem,4vw,3.2rem)] leading-[1] font-extrabold">
              Pick the cleaner for the job.
            </h2>
            <p className="mt-5 text-lg leading-relaxed text-ink-soft">
              {name} is the one for shrinking videos, Live Photos, and screenshots instead of deleting them. Pro
              starts at {formatPrice(plans.weekly.price)} a week, and scanning and deleting stay free. The others
              are better at a different job:
            </p>
          </div>
          <ul className="mt-8 max-w-2xl space-y-3 text-lg">
            {jobs.map((job) => (
              <li key={job.href}>
                <Link href={job.href} className="font-semibold underline decoration-mint decoration-[3px] underline-offset-4 hover:decoration-ink">
                  {job.name}
                </Link>
                <span className="text-ink-soft">{` — ${job.label}.`}</span>
              </li>
            ))}
          </ul>
          <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {ready.map((competitor, i) => (
              <CompareCard key={competitor.slug} competitor={competitor} index={i} />
            ))}
          </div>
        </section>

        <section className="mx-auto grid max-w-6xl gap-12 px-5 pb-8 sm:px-8 lg:grid-cols-[0.8fr_1.2fr]">
          <div>
            <p className="eyebrow">questions</p>
            <h2 className="mt-3 font-display text-[clamp(2rem,4vw,3.2rem)] leading-[1] font-extrabold">
              Good questions, straight answers.
            </h2>
          </div>
          <FaqList items={faqHtml} />
        </section>

        <section id="get-app" className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
          <div className="misprint rounded-[32px]">
            <div className="rounded-[32px] border-[2.5px] border-ink bg-surface px-7 py-14 sm:px-12">
              <h2 className="max-w-xl font-display text-[clamp(2rem,4.5vw,3.2rem)] leading-[1] font-extrabold">
                Keep the memories. Lose the bulk.
              </h2>
              <p className="mt-4 max-w-lg text-lg text-ink-soft">
                {name} shrinks your videos, photos, and screenshots instead of deleting them. You confirm every
                change. <Link href="/pricing" className="font-semibold text-ink underline decoration-mint decoration-[3px] underline-offset-4">See pricing.</Link>
              </p>
              <div className="mt-8">
                <AppCta campaign="compare-hub" />
              </div>
            </div>
          </div>
        </section>
      </main>
      <SiteFooter />
      <JsonLd
        data={graph(
          {
            "@type": "CollectionPage",
            name: `${title} | ${name}`,
            description,
            url: absoluteUrl("/compare"),
            mainEntity: {
              "@type": "ItemList",
              itemListElement: ready.map((c, i) => ({
                "@type": "ListItem",
                position: i + 1,
                name: `${name} vs ${c.name}`,
                url: absoluteUrl(compareHref(c.slug)),
              })),
            },
          },
          faqSchema(faq),
          breadcrumbSchema([
            { name: "Home", path: "/" },
            { name: "Compare", path: "/compare" },
          ]),
        )}
      />
    </>
  );
}
