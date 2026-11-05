import type { CSSProperties } from "react";
import type { Metadata } from "next";
import { AppCta } from "@/components/app-cta";
import { FaqList } from "@/components/faq-list";
import { Illustration, type IllustrationName } from "@/components/ink";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { markdownToHtml } from "@/lib/guides";
import {
  annualPerWeek,
  annualSavingsPercent,
  formatPrice,
  freeFeatures,
  plans,
  proFeatures,
} from "@/lib/pricing";
import { faqSchema, graph } from "@/lib/schema";
import { siteConfig } from "@/lib/site";

const name = siteConfig.name;

export const metadata: Metadata = {
  title: "Pricing",
  description: `${name} is free to scan your iPhone and clean it up by hand. ${name} Pro shrinks videos, Live Photos and screenshots, and cleans up your photos in one tap, from ${formatPrice(plans.weekly.price)} a week.`,
  alternates: { canonical: "/pricing" },
};

const faq = [
  {
    q: "Is there a free trial?",
    a: `No, but you don't need one to know if it's worth it. The free scan shows exactly how much space Pro would save on your iPhone before you pay anything.`,
  },
  {
    q: "How do I cancel?",
    a: "Any time, in **Settings → your name → Subscriptions** on your iPhone. You keep Pro until the end of the period you've paid for.",
  },
  {
    q: "What stays free?",
    a: `Everything you do by hand: scanning, browsing and deleting, Swipe to clean, keeping the best shot of each burst, cleaning up a folder in Files, and the guides for other apps. Pro adds the tools that shrink files instead of deleting them, and does the big cleanups in one tap.`,
  },
  {
    q: "What happens to shrunk files if I cancel?",
    a: "Nothing. Anything you've already compressed, trimmed, or converted stays that way, and originals you haven't cleared are still in Recently Deleted.",
  },
  {
    q: "Can I get a refund?",
    a: "Purchases go through Apple, so refunds do too. Request one at reportaproblem.apple.com.",
  },
];

export default function PricingPage() {
  const faqHtml = faq.map((item) => ({ q: item.q, a: markdownToHtml(item.a) }));

  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1 overflow-x-clip">
        {/* ── Header ───────────────────────────────────────────── */}
        <section className="relative mx-auto max-w-6xl px-5 pt-16 pb-14 text-center sm:px-8 sm:pt-24">
          <div
            aria-hidden="true"
            className="pointer-events-none absolute top-0 left-1/2 h-[520px] w-[520px] -translate-x-1/2 rounded-full bg-[radial-gradient(circle,var(--mint-soft)_0,transparent_65%)] opacity-80 blur-2xl"
          />
          <div className="relative">
            <p className="eyebrow">pricing</p>
            <h1 className="mx-auto mt-4 max-w-3xl font-display text-[clamp(2.6rem,6vw,4.6rem)] leading-[0.98] font-extrabold">
              Free by hand. Pro in one tap.
            </h1>
            <p className="mx-auto mt-6 max-w-xl text-lg text-ink-soft">
              See everything filling your iPhone and clean it up yourself for free. Upgrade when you want it smaller instead of gone, or all done at once.
            </p>
          </div>
        </section>

        {/* ── Plans ────────────────────────────────────────────── */}
        <section aria-label="Plans" className="mx-auto max-w-6xl px-5 pb-24 sm:px-8">
          <div className="grid items-stretch gap-8 lg:grid-cols-3">
            <PlanCard
              index={0}
              title="Free"
              price="$0"
              cadence="forever"
              note="No account, no card."
              features={freeFeatures}
              illustration="ill-trash"
            />
            <PlanCard
              index={1}
              title="Pro Weekly"
              price={formatPrice(plans.weekly.price)}
              cadence="per week"
              note="Billed weekly. Cancel anytime."
              features={proFeatures}
              illustration="ill-compress"
            />
            <PlanCard
              index={2}
              title="Pro Annual"
              price={formatPrice(plans.annual.price)}
              cadence="per year"
              note={`Just ${formatPrice(annualPerWeek)} a week, billed yearly.`}
              badge={`Save ${annualSavingsPercent}%`}
              features={proFeatures}
              illustration="ill-piggy"
              featured
            />
          </div>
          <p className="font-hand mt-10 text-center text-xl text-ink-soft">
            Prices in USD. Subscriptions renew automatically until you cancel.
          </p>
        </section>

        {/* ── FAQ ──────────────────────────────────────────────── */}
        <section className="mx-auto grid max-w-6xl gap-12 px-5 pb-28 sm:px-8 lg:grid-cols-[0.8fr_1.2fr]">
          <div data-reveal>
            <p className="eyebrow">billing questions</p>
            <h2 className="mt-3 font-display text-[clamp(2.2rem,4.5vw,3.6rem)] leading-[1] font-extrabold">
              No surprises on your bill.
            </h2>
            <Illustration name="ill-shield-check" size={110} className="mt-8 hidden -rotate-6 lg:block" />
          </div>
          <div data-reveal style={{ "--reveal-delay": 120 } as CSSProperties}>
            <FaqList items={faqHtml} />
          </div>
        </section>

        {/* ── CTA ──────────────────────────────────────────────── */}
        <section id="get-app" className="mx-auto max-w-3xl px-5 pb-28 sm:px-8">
          <div className="sticker p-8 sm:p-10">
            <p className="font-display text-3xl font-bold">Start free. Upgrade if it earns it.</p>
            <p className="mt-3 text-ink-soft">Your first scan costs nothing and never leaves your phone.</p>
            <div className="mt-7">
              <AppCta campaign="pricing" />
            </div>
          </div>
        </section>
      </main>
      <SiteFooter />
      <JsonLd data={graph(faqSchema(faq))} />
    </>
  );
}

function PlanCard({
  index,
  title,
  price,
  cadence,
  note,
  badge,
  features,
  illustration,
  featured = false,
}: {
  index: number;
  title: string;
  price: string;
  cadence: string;
  note: string;
  badge?: string;
  features: string[];
  illustration: IllustrationName;
  featured?: boolean;
}) {
  const card = (
    <article className={`sticker flex h-full flex-col p-7 ${featured ? "bg-mint-soft" : ""}`}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="font-display text-2xl font-bold">{title}</h2>
          {badge && (
            <p className="mt-2 inline-block rounded-full border-2 border-ink bg-mint px-3 py-0.5 text-sm font-bold">
              {badge}
            </p>
          )}
        </div>
        <Illustration name={illustration} size={64} className="shrink-0 -rotate-6" />
      </div>
      <p className="mt-6 flex items-baseline gap-2">
        <span className="font-display text-5xl leading-none font-extrabold tracking-tight">{price}</span>
        <span className="text-ink-soft">{cadence}</span>
      </p>
      <p className="font-hand mt-2 text-[1.05rem] leading-snug text-ink-soft">{note}</p>
      <hr className="my-6 border-t-2 border-dashed border-ink/20" />
      <ul className="space-y-3">
        {features.map((feature) => (
          <li key={feature} className="flex gap-3 leading-snug">
            <span aria-hidden="true" className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border-2 border-ink bg-mint text-[0.7rem] font-black">
              ✓
            </span>
            {feature}
          </li>
        ))}
      </ul>
    </article>
  );

  // The reveal observer adds `is-in` to the data-reveal element, so it gets no
  // React-managed className of its own (that would mismatch on hydration).
  return (
    <div data-reveal style={{ "--reveal-delay": index * 100 } as CSSProperties}>
      <div className={`h-full ${featured ? "misprint rounded-[24px]" : ""}`}>{card}</div>
    </div>
  );
}
