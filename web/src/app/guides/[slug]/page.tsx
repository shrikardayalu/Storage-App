import { Fragment, type CSSProperties } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { AppCta } from "@/components/app-cta";
import { FaqList } from "@/components/faq-list";
import { GuideCard } from "@/components/guide-card";
import { Illustration, Scribble } from "@/components/ink";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { StickyCta } from "@/components/sticky-cta";
import { getAllGuides, getGuide, getRelatedGuides, type GuideMeta } from "@/lib/guides";
import { articleSchema, breadcrumbSchema, faqSchema, graph } from "@/lib/schema";
import { siteConfig } from "@/lib/site";
import { getTopic } from "@/lib/topics";

// Every guide is prerendered from generateStaticParams, so the whole article is
// in the static HTML (what crawlers need). Only unknown slugs render on demand,
// and those just 404, so there's no loading shell worth streaming.
export const instant = false;

export function generateStaticParams() {
  return getAllGuides().map((guide) => ({ slug: guide.slug }));
}

export async function generateMetadata({ params }: PageProps<"/guides/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const guide = getGuide(slug);
  if (!guide) return {};

  return {
    title: guide.seoTitle,
    description: guide.description,
    alternates: { canonical: `/guides/${guide.slug}` },
    openGraph: {
      type: "article",
      siteName: siteConfig.name,
      locale: siteConfig.locale,
      title: guide.seoTitle,
      description: guide.description,
      url: `/guides/${guide.slug}`,
      publishedTime: guide.published,
      modifiedTime: guide.updated,
    },
    twitter: { card: "summary_large_image", title: guide.seoTitle, description: guide.description },
  };
}

const formatDate = (date: string) =>
  new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  });

function defaultCta(guide: GuideMeta) {
  return {
    title: "Free up space without deleting",
    body: `${siteConfig.name} shrinks 4K videos, trims long recordings, and keeps Live Photos as stills, so your library stays whole and your phone gets lighter. Nothing changes until you confirm.`,
    // App Store campaign tokens max out at 40 characters.
    campaign: `g-${guide.slug.slice(0, 30)}`,
  };
}

export default async function GuidePage({ params }: PageProps<"/guides/[slug]">) {
  const { slug } = await params;
  const guide = getGuide(slug);
  if (!guide) notFound();

  const topic = getTopic(guide.topic);
  const related = getRelatedGuides(guide);
  const cta = { ...defaultCta(guide), ...guide.cta };
  const crumbs = [
    { name: "Home", path: "/" },
    { name: "Guides", path: "/guides" },
    { name: guide.title, path: `/guides/${guide.slug}` },
  ];

  return (
    <>
      <SiteHeader />

      <main id="main" className="flex-1 overflow-x-clip">
        <article>
          {/* ── Header ─────────────────────────────────────────── */}
          <header className="mx-auto max-w-6xl px-5 pt-10 sm:px-8 sm:pt-14">
            <nav aria-label="Breadcrumb" className="text-sm text-ink-faint">
              <ol className="flex flex-wrap items-center gap-1.5">
                <li>
                  <Link href="/" className="hover:text-ink">Home</Link>
                </li>
                <li aria-hidden="true">/</li>
                <li>
                  <Link href="/guides" className="hover:text-ink">Guides</Link>
                </li>
                <li aria-hidden="true">/</li>
                <li>
                  <Link href={`/guides#${guide.topic}`} className="hover:text-ink">{topic?.name}</Link>
                </li>
              </ol>
            </nav>

            <div className="mt-8 grid items-end gap-8 lg:grid-cols-[1fr_auto]">
              <div className="max-w-3xl">
                <h1 className="font-display text-[clamp(2.4rem,5.5vw,4.2rem)] leading-[0.98] font-extrabold text-balance">
                  {guide.title}
                </h1>
                <p className="mt-5 text-lg leading-relaxed text-pretty text-ink-soft sm:text-xl">{guide.description}</p>
                <p className="mt-6 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-ink-faint">
                  <span>
                    By the{" "}
                    <Link href="/about" className="font-semibold text-ink-soft hover:text-ink">
                      {siteConfig.name} team
                    </Link>
                  </span>
                  <span aria-hidden="true">·</span>
                  <span>
                    Updated <time dateTime={guide.updated}>{formatDate(guide.updated)}</time>
                  </span>
                  <span aria-hidden="true">·</span>
                  <span>{guide.readingMinutes} min read</span>
                </p>
              </div>
              <Illustration name={guide.illustration} size={150} priority className="hidden -rotate-6 lg:block" />
            </div>
          </header>

          <div className="mx-auto grid max-w-6xl gap-12 px-5 pt-10 pb-20 sm:px-8 lg:grid-cols-[minmax(0,1fr)_280px] lg:gap-16">
            <div className="min-w-0 max-w-[44rem]">
              {/* ── Quick answer (the snippet answer engines lift) ── */}
              <section aria-labelledby="quick-answer" className="sticker bg-mint-soft p-6 sm:p-7">
                <h2 id="quick-answer" className="font-hand text-2xl text-mint-deep">
                  Quick answer
                </h2>
                <div
                  className="prose-guide mt-2 !text-[1.1rem] !text-ink"
                  dangerouslySetInnerHTML={{ __html: guide.quickAnswerHtml }}
                />
              </section>

              {/* ── Body, with a CTA wherever the author placed a marker ── */}
              <div className="mt-12">
                {guide.segments.map((html, i) => (
                  <Fragment key={i}>
                    <div className="prose-guide" dangerouslySetInnerHTML={{ __html: html }} />
                    {i < guide.segments.length - 1 && (
                      <InlineCta title={cta.title} body={cta.body} campaign={`${cta.campaign}-${i + 1}`} />
                    )}
                  </Fragment>
                ))}
              </div>

              {guide.faqHtml.length > 0 && (
                <section aria-labelledby="faq" className="mt-20">
                  <h2 id="faq" className="mb-6 font-display text-3xl font-extrabold">
                    Frequently asked questions
                  </h2>
                  <FaqList items={guide.faqHtml} />
                </section>
              )}
            </div>

            {/* ── Sidebar ──────────────────────────────────────── */}
            <aside className="hidden lg:block">
              <div className="sticky top-24 space-y-8">
                {guide.toc.length > 1 && (
                  <nav aria-label="On this page">
                    <p className="text-xs font-bold tracking-widest text-ink-faint uppercase">On this page</p>
                    <ol className="mt-4 space-y-1 border-l-2 border-ink/10 text-sm">
                      {guide.toc.map((entry) => (
                        <li key={entry.id}>
                          <a
                            href={`#${entry.id}`}
                            className="-ml-[2px] block border-l-2 border-transparent py-1.5 pl-4 text-ink-soft transition-colors hover:border-mint hover:text-ink"
                          >
                            {entry.text}
                          </a>
                        </li>
                      ))}
                    </ol>
                  </nav>
                )}
                <div className="sticker p-5">
                  <Illustration name="ill-phone-sparkle" size={56} />
                  <p className="mt-3 font-display text-lg leading-tight font-bold">{cta.title}</p>
                  <a href="#get-app" className="btn-ink mt-4 w-full px-4 py-2.5 text-sm">
                    {siteConfig.appStoreUrl ? "Get the app" : "Get early access"}
                  </a>
                </div>
              </div>
            </aside>
          </div>
        </article>

        {/* ── Related ──────────────────────────────────────────── */}
        {related.length > 0 && (
          <section aria-labelledby="related" className="border-t-2 border-ink bg-surface">
            <div className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
              <h2 id="related" className="font-display text-3xl font-extrabold">
                Keep reading
              </h2>
              <div className="mt-10 grid gap-x-6 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
                {related.map((g, i) => (
                  <GuideCard key={g.slug} guide={g} index={i} />
                ))}
              </div>
            </div>
          </section>
        )}

        {/* ── End CTA ──────────────────────────────────────────── */}
        <section id="get-app" className="bg-ink text-paper">
          <div className="relative mx-auto max-w-6xl overflow-hidden px-5 py-20 sm:px-8">
            <div className="relative z-10 max-w-xl">
              <p className="font-hand text-2xl text-mint">the faster way</p>
              <h2 className="mt-2 font-display text-[clamp(2rem,4.5vw,3.3rem)] leading-[1] font-extrabold">
                {cta.title}
              </h2>
              <p className="mt-4 text-lg text-paper/70">{cta.body}</p>
              <div className="mt-8">
                <AppCta campaign={`${cta.campaign}-end`} tone="dark" />
              </div>
            </div>
            <Illustration
              name={guide.illustration}
              size={260}
              className="pointer-events-none absolute -right-10 -bottom-10 hidden rotate-12 opacity-25 grayscale invert md:block"
            />
          </div>
        </section>
      </main>

      <SiteFooter />
      <StickyCta label={cta.title} />
      <JsonLd
        data={graph(
          articleSchema(guide),
          breadcrumbSchema(crumbs),
          ...(guide.faq.length ? [faqSchema(guide.faq)] : []),
        )}
      />
    </>
  );
}

function InlineCta({ title, body, campaign }: { title: string; body: string; campaign: string }) {
  return (
    <aside
      aria-label="About the app"
      className="sticker my-12 overflow-hidden p-6 sm:p-8"
      data-reveal
      style={{ "--reveal-delay": 0 } as CSSProperties}
    >
      <div className="flex items-start gap-5">
        <Illustration name="ill-phone-sparkle" size={64} className="hidden shrink-0 sm:block" />
        <div className="min-w-0">
          <p className="relative inline-block font-display text-xl leading-tight font-bold text-ink">
            {title}
            <Scribble className="absolute -bottom-2 left-0 h-2.5 w-full text-mint" delay={0} />
          </p>
          <p className="mt-3 text-base leading-relaxed text-ink-soft">{body}</p>
          <div className="mt-5">
            <AppCta campaign={campaign} />
          </div>
        </div>
      </div>
    </aside>
  );
}
