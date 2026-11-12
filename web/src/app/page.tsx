import type { CSSProperties } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { AppCta } from "@/components/app-cta";
import { CompareCard } from "@/components/compare-card";
import { TodoBanner } from "@/components/todo-banner";
import { FaqList } from "@/components/faq-list";
import { GuideCard } from "@/components/guide-card";
import { HowItWorks } from "@/components/how-it-works";
import { Illustration, InkArrow, Scribble, Sparks, Strike, type IllustrationName } from "@/components/ink";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { SpaceReceipt } from "@/components/space-receipt";
import { competitors } from "@/lib/comparisons";
import { getAllGuides, guideHref, markdownToHtml } from "@/lib/guides";
import { formatPrice, plans } from "@/lib/pricing";
import { appSchema, faqSchema, graph } from "@/lib/schema";
import { siteConfig } from "@/lib/site";

const name = siteConfig.name;

export const metadata: Metadata = {
  alternates: { canonical: "/" },
};

const faq = [
  {
    q: `Is ${name} free?`,
    a: `Scanning, browsing, and deleting are free. Pro adds the tools that shrink videos, Live Photos, and screenshots instead of deleting them, from ${formatPrice(plans.weekly.price)} a week. [See the plans](/pricing).`,
  },
  {
    q: "Will compressed videos and photos look worse?",
    a: "You choose the level. **Light** is barely noticeable, **Balanced** keeps good quality at a much smaller size, and **Maximum** is smallest with some visible softening. You see the savings before anything changes.",
  },
  {
    q: "Will it change anything automatically?",
    a: "No. Nothing is compressed, trimmed, converted, or deleted until you select it and confirm.",
  },
  {
    q: "What happens to the originals?",
    a: `They go to the **Recently Deleted** album in Photos, where you can recover them for about 30 days. Compare, then empty it when you're happy. Here's [how iPhone storage cleanup works](${guideHref("iphone-storage-full")}) step by step.`,
  },
  {
    q: "Does it upload my photos anywhere?",
    a: "No. Your library is analyzed on your iPhone, and your photos and videos are never sent to our servers.",
  },
  {
    q: "Can it clear System Data or other apps' caches?",
    a: `No, and no App Store app can: iOS keeps every app sandboxed. Be wary of any app that says otherwise. Our guide on [shrinking iPhone System Data](${guideHref("iphone-system-data-too-large")}) covers what actually works.`,
  },
  {
    q: "When does it launch?",
    a: "Soon. Join the waitlist and we'll send exactly one email on launch day.",
  },
];

const marquee = [
  "4K video of a two-minute toast",
  "9-minute screen recordings",
  "2,000 PNG screenshots",
  "Live Photos of your lunch",
  "burst shots, all 40 of them",
  "slo-mo of a dog",
  "the same meme, saved six times",
];

type Method = {
  stat: string;
  statNote: string;
  title: string;
  body: string;
  illustration: IllustrationName;
  guide?: { href: string; label: string };
  tone: "surface" | "mint";
};

// Savings figures are either Apple's published numbers or plain arithmetic on
// the example given. Keep them that way.
const methods: Method[] = [
  {
    stat: "−85%",
    statNote: "4K 60 fps → 1080p, per Apple's own size estimates",
    title: "Shrink 4K videos",
    body: "A minute of 4K at 60 fps is about 400 MB. The same minute at 1080p is about 60 MB, and on a phone screen it's hard to tell apart.",
    illustration: "ill-video",
    guide: { href: guideHref("compress-videos-iphone"), label: "How video compression works" },
    tone: "surface",
  },
  {
    stat: "−93%",
    statNote: "example: keeping 40 s of a 9-minute clip",
    title: "Trim to the good part",
    body: "Long recordings are mostly waiting around. Keep the moment, cut the rest, and the file shrinks with it.",
    illustration: "ill-reset",
    guide: { href: guideHref("compress-videos-iphone"), label: "Trimming videos on iPhone" },
    tone: "mint",
  },
  {
    stat: "3 sec",
    statNote: "of hidden video inside every Live Photo",
    title: "Keep Live Photos as stills",
    body: "Every Live Photo carries a short video alongside the picture. For the thousands you'll never animate, the still is all you need.",
    illustration: "ill-photo",
    guide: { href: guideHref("live-photos-storage-iphone"), label: "Do Live Photos take more space?" },
    tone: "surface",
  },
  {
    stat: "PNG",
    statNote: "the lossless format iPhone saves screenshots in",
    title: "Re-save screenshots",
    body: "Screenshots are stored in a format built for perfect copies, not small files. Re-saved, they look the same and take far less room.",
    illustration: "ill-screenshot",
    tone: "surface",
  },
  {
    stat: "1 of 40",
    statNote: "frames you actually want from a burst",
    title: "Keep the best shot",
    body: "Bursts and near-identical photos pile up fast. Pick the keeper from each set and let the rest go.",
    illustration: "ill-stack-small",
    guide: { href: guideHref("delete-duplicate-photos-iphone"), label: "Finding duplicates and bursts" },
    tone: "mint",
  },
];

export default function Home() {
  const guides = getAllGuides().slice(0, 6);
  const faqHtml = faq.map((item) => ({ q: item.q, a: markdownToHtml(item.a) }));

  return (
    <>
      <SiteHeader />

      <main id="main" className="flex-1 overflow-x-clip">
        {/* ── Hero ─────────────────────────────────────────────── */}
        <section className="home-hero relative" aria-labelledby="hero-heading">
          <div
            aria-hidden="true"
            className="pointer-events-none absolute top-10 right-[-10%] h-[620px] w-[620px] rounded-full bg-[radial-gradient(circle,var(--mint-soft)_0,transparent_65%)] opacity-80 blur-2xl"
          />
          <div className="hero-layout relative mx-auto grid max-w-6xl items-center gap-x-16 px-5 sm:px-8 lg:grid-cols-[1.1fr_0.9fr]">
            <div className="hero-copy min-w-0">
              <p className="hero-eyebrow eyebrow flex items-center gap-2">
                <Sparks className="size-6 text-mint-deep" />
                for iPhone · {siteConfig.appStoreUrl ? "free on the App Store" : "launching soon"}
              </p>
              <h1 id="hero-heading" className="hero-title mt-5 font-display leading-[0.93] font-extrabold">
                <span className="hero-title-line">Storage <span className="whitespace-nowrap">almost full.</span></span>
                <br />
                <span className="relative inline-block">
                  Again?
                  <Scribble className="absolute -bottom-3 left-0 h-4 w-full text-mint" />
                </span>
              </h1>
              <p className="hero-description mt-8 max-w-xl text-lg leading-relaxed text-pretty text-ink-soft sm:text-xl">
                {name} makes what you already have take up less space.{" "}
                <span className="font-semibold text-ink">
                  Shrink videos, trim long recordings, and turn Live Photos into stills.
                </span>
              </p>
              <div className="hero-cta mt-9">
                <AppCta campaign="home-hero" />
              </div>
            </div>

            <ul className="hero-assurances flex flex-wrap gap-x-6 gap-y-3 text-sm font-medium text-ink-soft">
              {["Nothing changes until you confirm", "Originals kept for 30 days", "Works on your iPhone"].map(
                (item) => (
                  <li key={item} className="flex items-center gap-2">
                    <span
                      aria-hidden="true"
                      className="grid size-5 shrink-0 place-items-center rounded-full bg-mint text-[11px] font-bold text-ink"
                    >
                      ✓
                    </span>
                    {item}
                  </li>
                ),
              )}
            </ul>

            <div className="hero-receipt relative mx-auto w-full max-w-[400px] lg:mr-0" data-reveal>
              <div className="parallax" style={{ "--depth": 14 } as CSSProperties}>
                <div className="rotate-[1.5deg]">
                  <SpaceReceipt />
                </div>
              </div>
              <Illustration
                name="ill-compress"
                size={96}
                priority
                className="hero-compress bob absolute -top-12 -left-6 sm:-left-16"
                style={{ "--r": "-10deg" } as CSSProperties}
              />
              <Illustration
                name="ill-piggy"
                size={88}
                priority
                className="bob absolute -bottom-10 -left-4 hidden sm:-left-20 sm:block"
                style={{ "--r": "8deg", "--bob-delay": "-3s" } as CSSProperties}
              />
              <p className="font-hand absolute -top-12 right-2 hidden rotate-[5deg] text-2xl sm:block">
                watch it shrink ↓
              </p>
            </div>
          </div>
        </section>

        {/* ── Marquee ──────────────────────────────────────────── */}
        <div className="-rotate-1 border-y-2 border-ink bg-band py-4 text-on-band" aria-hidden="true">
          <div className="marquee flex w-max gap-10 whitespace-nowrap">
            {[...marquee, ...marquee].map((item, i) => (
              <span key={i} className="font-hand flex items-center gap-10 text-2xl">
                {item}
                <span className="text-mint">✦</span>
              </span>
            ))}
          </div>
        </div>

        {/* ── The problem ──────────────────────────────────────── */}
        <section className="mx-auto grid max-w-6xl items-center gap-16 px-5 py-28 sm:px-8 lg:grid-cols-2">
          <div data-reveal>
            <p className="eyebrow">the problem</p>
            <h2 className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold">
              Your iPhone has one answer: delete something.
            </h2>
            <p className="mt-6 max-w-lg text-lg leading-relaxed text-ink-soft">
              Settings can sort your apps by size, and Photos can delete. That&apos;s where the help stops.
              There&apos;s no button to shrink a 4K video you want to keep, and trimming or converting happens
              one file at a time.
            </p>
            <p className="mt-4 max-w-lg text-lg leading-relaxed text-ink">
              {name} frees up space the other way: by making things smaller.
            </p>
          </div>

          <div className="relative flex justify-center py-6" data-reveal style={{ "--reveal-delay": 150 } as CSSProperties}>
            <div className="absolute inset-x-6 inset-y-0 rounded-[40px] bg-[radial-gradient(circle_at_30%_30%,var(--mint)_0,transparent_60%),radial-gradient(circle_at_80%_70%,var(--mint-soft)_0,transparent_55%)] opacity-70 blur-2xl" />
            <div
              role="img"
              aria-label="The iPhone 'Storage Almost Full' alert"
              className="relative w-[290px] overflow-hidden rounded-[26px] bg-surface/80 text-center shadow-[0_30px_60px_-20px_rgb(26_26_23/0.35)] ring-1 ring-ink/10 backdrop-blur-xl"
            >
              <div className="px-5 pt-5 pb-4">
                <p className="text-[17px] font-semibold">Storage Almost Full</p>
                <p className="mt-1 text-[13px] leading-snug text-ink-soft">
                  You can manage your storage in Settings.
                </p>
              </div>
              <div className="grid grid-cols-2 border-t border-ink/10 text-[17px] text-[#0a72e8]">
                <span className="border-r border-ink/10 py-3">Not Now</span>
                <span className="py-3 font-semibold">Settings</span>
              </div>
            </div>
            <InkArrow className="absolute -top-8 right-0 h-20 w-24 -scale-x-100 text-ink sm:right-6" />
            <p className="font-hand absolute -top-14 right-14 rotate-[4deg] text-2xl sm:right-28">
              …then what?
            </p>
          </div>
        </section>

        {/* ── How it works (pinned scroll) ─────────────────────── */}
        <section id="how-it-works" className="border-y-2 border-ink bg-surface">
          <div className="mx-auto max-w-6xl px-5 py-24 sm:px-8 lg:py-10">
            <div className="lg:hidden">
              <p className="eyebrow">how it works</p>
              <h2 className="mt-3 font-display text-4xl font-extrabold">Same memories. Lighter phone.</h2>
            </div>
            <h2 className="sr-only lg:not-sr-only lg:block lg:pt-20 lg:text-center lg:font-display lg:text-5xl lg:font-extrabold">
              Same memories. Lighter phone.
            </h2>
            <HowItWorks />
          </div>
        </section>

        {/* ── Methods: free space without deleting ─────────────── */}
        <section id="methods" className="mx-auto max-w-6xl px-5 py-28 sm:px-8" aria-labelledby="methods-heading">
          <div className="grid items-end gap-6 lg:grid-cols-[1.2fr_0.8fr]" data-reveal>
            <div>
              <p className="eyebrow">beyond the delete button</p>
              <h2
                id="methods-heading"
                className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold"
              >
                Five ways to free space without losing a memory.
              </h2>
            </div>
            <p className="text-lg leading-relaxed text-ink-soft">
              Deleting is the last resort. Most of the space on a full iPhone is in files that could simply be
              smaller.
            </p>
          </div>

          <div className="mt-14 grid gap-6 md:grid-cols-2 lg:grid-cols-3">
            {methods.map((method, i) => (
              <MethodCard key={method.title} method={method} index={i} />
            ))}
            <div
              className="sticker flex flex-col justify-between bg-band p-7 text-on-band"
              data-reveal
              style={{ "--reveal-delay": 200 } as CSSProperties}
            >
              <div>
                <p className="font-hand text-xl text-mint">…and the real junk</p>
                <h3 className="mt-3 font-display text-2xl font-bold">Then, and only then, delete.</h3>
                <p className="mt-3 text-on-band/70">
                  Accidental recordings, pocket photos, and screenshots you&apos;ll never need again, gathered in
                  one place. You approve every one.
                </p>
              </div>
              <div className="mt-6 flex items-center justify-between">
                <a href="#get-app" className="btn-ink bg-on-band px-5 py-2.5 text-sm text-band">
                  {siteConfig.appStoreUrl ? "Get the app" : "Get early access"}
                </a>
                <Illustration name="ill-trash" size={64} className="rounded-2xl bg-mint-soft p-1.5" />
              </div>
            </div>
          </div>
        </section>

        {/* ── Honest by default ────────────────────────────────── */}
        <section className="bg-paper-deep/60">
          <div className="mx-auto grid max-w-6xl items-center gap-14 px-5 py-28 sm:px-8 lg:grid-cols-2">
            <div data-reveal>
              <p className="eyebrow">honest by default</p>
              <h2 className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold">
                No fake scans. No scary warnings.
              </h2>
              <p className="mt-6 max-w-lg text-lg leading-relaxed text-ink-soft">
                Plenty of &ldquo;cleaner&rdquo; apps promise things iOS doesn&apos;t let any app do. We&apos;d
                rather tell you what really frees space, then help you do it.
              </p>
              <Link
                href={guideHref("are-iphone-cleaner-apps-safe")}
                className="mt-7 inline-flex items-center gap-2 font-semibold underline decoration-mint decoration-[3px] underline-offset-4 hover:decoration-ink"
              >
                Are iPhone cleaner apps safe? <span aria-hidden="true">→</span>
              </Link>
            </div>

            <div className="grid gap-5 sm:grid-cols-2">
              <div className="sticker rotate-[-1.5deg] p-6" data-reveal>
                <p className="font-hand text-xl text-tomato">things no app can do</p>
                <ul className="mt-4 space-y-4 font-display text-lg font-semibold">
                  {["Boost your RAM", "Remove viruses", "Wipe System Data", "Clear other apps' caches"].map((claim) => (
                    <li key={claim} className="relative w-fit text-ink-faint">
                      {claim}
                      <Strike className="absolute top-1/2 -left-1 h-3 w-[110%] -translate-y-1/2" />
                    </li>
                  ))}
                </ul>
              </div>
              <div className="sticker rotate-[1.5deg] bg-mint-soft p-6" data-reveal style={{ "--reveal-delay": 150 } as CSSProperties}>
                <p className="font-hand text-xl text-mint-deep">what actually works</p>
                <ul className="mt-4 space-y-4 font-display text-lg font-semibold">
                  {["Shrinking 4K videos", "Trimming long recordings", "Live Photos kept as stills", "Clearing true clutter"].map(
                    (item) => (
                      <li key={item} className="flex items-center gap-2.5">
                        <span aria-hidden="true" className="grid size-6 shrink-0 place-items-center rounded-full border-2 border-ink bg-mint text-xs">
                          ✓
                        </span>
                        {item}
                      </li>
                    ),
                  )}
                </ul>
              </div>
            </div>
          </div>
        </section>

        {/* ── Compare ──────────────────────────────────────────── */}
        <section id="compare" className="mx-auto max-w-6xl px-5 pt-28 sm:px-8" aria-labelledby="compare-heading">
          <div className="grid items-end gap-6 lg:grid-cols-[1.2fr_0.8fr]" data-reveal>
            <div>
              <p className="eyebrow">how we compare</p>
              <h2
                id="compare-heading"
                className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold"
              >
                {name} vs. the popular cleaners.
              </h2>
            </div>
            <p className="text-lg leading-relaxed text-ink-soft">
              Most cleaners help you find things to delete. Here&apos;s an honest look at where each one shines,
              and where shrinking beats deleting.
            </p>
          </div>
          {competitors.some((c) => !c.ready) && (
            <div className="mt-10">
              <TodoBanner title="Write the comparison articles">
                {competitors.filter((c) => !c.ready).length} of {competitors.length} comparisons are still
                &ldquo;coming soon&rdquo; placeholders (hidden from Google):{" "}
                {competitors
                  .filter((c) => !c.ready)
                  .map((c) => c.name)
                  .join(", ")}
                . Write each one, then set <code>ready: true</code> in <code>web/src/lib/comparisons.ts</code>. This
                banner disappears once they&apos;re all ready.
              </TodoBanner>
            </div>
          )}
          <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {competitors.map((competitor, i) => (
              <CompareCard key={competitor.slug} competitor={competitor} index={i} />
            ))}
          </div>
        </section>

        {/* ── Guides ───────────────────────────────────────────── */}
        {guides.length > 0 && (
          <section className="mx-auto max-w-6xl px-5 py-28 sm:px-8" aria-labelledby="guides-heading">
            <div className="flex flex-wrap items-end justify-between gap-6" data-reveal>
              <div className="max-w-2xl">
                <p className="eyebrow">free guides</p>
                <h2 id="guides-heading" className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold">
                  Fix it yourself. No app required.
                </h2>
                <p className="mt-5 text-lg text-ink-soft">
                  Straight answers using the tools already on your iPhone.
                </p>
              </div>
              <Link href="/guides" className="btn-ink px-5 py-3 text-sm">
                All guides →
              </Link>
            </div>
            <div className="mt-14 grid gap-x-6 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
              {guides.map((guide, i) => (
                <GuideCard key={guide.slug} guide={guide} index={i} />
              ))}
            </div>
          </section>
        )}

        {/* ── FAQ ──────────────────────────────────────────────── */}
        <section id="faq" className="mx-auto grid max-w-6xl gap-12 px-5 pb-28 sm:px-8 lg:grid-cols-[0.8fr_1.2fr]">
          <div data-reveal>
            <p className="eyebrow">questions</p>
            <h2 className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold">
              Good questions, straight answers.
            </h2>
            <Illustration name="ill-beaker" size={110} className="mt-8 hidden -rotate-6 lg:block" />
          </div>
          <div data-reveal style={{ "--reveal-delay": 120 } as CSSProperties}>
            <FaqList items={faqHtml} />
          </div>
        </section>

        {/* ── Final CTA ────────────────────────────────────────── */}
        <section id="get-app" className="mx-auto max-w-6xl px-5 pb-28 sm:px-8">
          <div className="misprint rounded-[36px]" data-reveal>
            <div className="relative overflow-hidden rounded-[36px] border-[2.5px] border-ink bg-surface px-7 py-16 sm:px-14 sm:py-20">
              <div className="relative z-10 max-w-xl">
                <h2 className="font-display text-[clamp(2.3rem,5vw,4rem)] leading-[0.98] font-extrabold">
                  Make room for the next thousand photos.
                </h2>
                <p className="mt-5 text-lg text-ink-soft">
                  {siteConfig.appStoreUrl
                    ? "Free to download. Find your first few gigabytes without deleting a thing."
                    : "Get one email on launch day, and be first in line."}
                </p>
                <div className="mt-8">
                  <AppCta campaign="home-footer" />
                </div>
              </div>
              <Illustration
                name="ill-phone-sparkle"
                size={210}
                className="pointer-events-none absolute right-10 bottom-10 hidden rotate-12 md:block"
              />
              <Illustration name="ill-piggy" size={110} className="bob absolute top-10 right-56 hidden lg:block" />
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
      <JsonLd data={graph(appSchema(), faqSchema(faq))} />
    </>
  );
}

function MethodCard({ method, index }: { method: Method; index: number }) {
  return (
    <article
      className={`sticker sticker-lift flex flex-col p-7 ${method.tone === "mint" ? "bg-mint-soft" : ""}`}
      data-reveal
      style={{ "--reveal-delay": (index % 3) * 100 } as CSSProperties}
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="font-display text-5xl leading-none font-extrabold tracking-tight">{method.stat}</p>
          <p className="font-hand mt-2 text-[1.05rem] leading-snug text-ink-soft">{method.statNote}</p>
        </div>
        <Illustration name={method.illustration} size={64} className="shrink-0 -rotate-6" />
      </div>
      <hr className="my-5 border-t-2 border-dashed border-ink/20" />
      <h3 className="font-display text-2xl font-bold">{method.title}</h3>
      <p className="mt-2 leading-relaxed text-ink-soft">{method.body}</p>
      {method.guide && (
        <Link
          href={method.guide.href}
          className="mt-auto inline-flex items-center gap-1.5 pt-6 text-sm font-semibold underline decoration-mint decoration-[3px] underline-offset-4 hover:decoration-ink"
        >
          {method.guide.label} <span aria-hidden="true">→</span>
        </Link>
      )}
    </article>
  );
}
