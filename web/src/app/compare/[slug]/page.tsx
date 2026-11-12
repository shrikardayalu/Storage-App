import { Fragment, type CSSProperties } from "react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { AppCta } from "@/components/app-cta";
import { AppIcon } from "@/components/app-icon";
import { CompareCard } from "@/components/compare-card";
import { FaqList } from "@/components/faq-list";
import { TodoBanner } from "@/components/todo-banner";
import { Illustration, Scribble } from "@/components/ink";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { StickyCta } from "@/components/sticky-cta";
import { getCompareArticle, type CompareArticle } from "@/lib/compare-articles";
import { competitors, getCompetitor, type Competitor } from "@/lib/comparisons";
import { breadcrumbSchema, compareSchema, faqSchema, graph } from "@/lib/schema";
import { siteConfig } from "@/lib/site";

export const instant = false;

export function generateStaticParams() {
  return competitors.map((c) => ({ slug: c.slug }));
}

export async function generateMetadata({ params }: PageProps<"/compare/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const competitor = getCompetitor(slug);
  if (!competitor) return {};

  const article = competitor.ready ? getCompareArticle(slug) : null;
  if (!article) {
    return {
      title: `${siteConfig.name} vs ${competitor.name}`,
      description: `How ${siteConfig.name} compares with ${competitor.name} for freeing up iPhone storage.`,
      alternates: { canonical: `/compare/${competitor.slug}` },
      // Placeholders shouldn't be indexed until the article is written.
      robots: { index: false, follow: true },
    };
  }

  return {
    // seoTitle already names the app, so skip the layout's "| name" suffix.
    title: { absolute: article.seoTitle },
    description: article.description,
    alternates: { canonical: `/compare/${slug}` },
    openGraph: {
      type: "article",
      siteName: siteConfig.name,
      locale: siteConfig.locale,
      title: article.seoTitle,
      description: article.description,
      url: `/compare/${slug}`,
      publishedTime: article.published,
      modifiedTime: article.updated,
    },
    twitter: { card: "summary_large_image", title: article.seoTitle, description: article.description },
  };
}

const formatDate = (date: string) =>
  new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  });

export default async function ComparePage({ params }: PageProps<"/compare/[slug]">) {
  const { slug } = await params;
  const competitor = getCompetitor(slug);
  if (!competitor) notFound();

  const others = competitors.filter((c) => c.slug !== competitor.slug).slice(0, 3);
  const article = competitor.ready ? getCompareArticle(slug) : null;

  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1 overflow-x-clip">
        {article ? <Article article={article} /> : <Placeholder competitor={competitor} />}

        <section aria-labelledby="more-compare" className="border-t-2 border-ink bg-surface">
          <div className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
            <h2 id="more-compare" className="font-display text-3xl font-extrabold">
              More comparisons
            </h2>
            <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {others.map((c, i) => (
                <CompareCard key={c.slug} competitor={c} index={i} />
              ))}
            </div>
          </div>
        </section>

        {article && (
          <section id="get-app" className="bg-band text-on-band">
            <div className="relative mx-auto max-w-6xl overflow-hidden px-5 py-20 sm:px-8">
              <div className="relative z-10 max-w-xl">
                <p className="font-hand text-2xl text-mint">see it on your phone</p>
                <h2 className="mt-2 font-display text-[clamp(2rem,4.5vw,3.3rem)] leading-[1] font-extrabold">
                  {article.cta.title}
                </h2>
                <p className="mt-4 text-lg text-on-band/70">{article.cta.body}</p>
                <div className="mt-8">
                  <AppCta campaign={`vs-${slug}-end`.slice(0, 40)} tone="dark" />
                </div>
              </div>
              <Illustration
                name="ill-compress"
                size={260}
                className="pointer-events-none absolute -right-10 -bottom-10 hidden rotate-12 opacity-25 grayscale invert md:block"
              />
            </div>
          </section>
        )}
      </main>
      <SiteFooter />
      {article && (
        <>
          <StickyCta label={article.cta.title} />
          <JsonLd
            data={graph(
              compareSchema(article),
              breadcrumbSchema([
                { name: "Home", path: "/" },
                { name: "Compare", path: "/#compare" },
                { name: article.title, path: `/compare/${slug}` },
              ]),
              ...(article.faq.length ? [faqSchema(article.faq)] : []),
            )}
          />
        </>
      )}
    </>
  );
}

function Breadcrumbs() {
  return (
    <nav aria-label="Breadcrumb" className="text-sm text-ink-faint">
      <ol className="flex flex-wrap items-center gap-1.5">
        <li>
          <Link href="/" className="hover:text-ink">Home</Link>
        </li>
        <li aria-hidden="true">/</li>
        <li>
          <Link href="/#compare" className="hover:text-ink">Compare</Link>
        </li>
      </ol>
    </nav>
  );
}

function Article({ article }: { article: CompareArticle }) {
  const { competitor } = article;
  const campaign = `vs-${competitor.slug}`.slice(0, 34);

  return (
    <article>
      <header className="mx-auto max-w-6xl px-5 pt-10 sm:px-8 sm:pt-14">
        <Breadcrumbs />
        <div className="mt-8 grid items-end gap-8 lg:grid-cols-[1fr_auto]">
          <div className="max-w-3xl">
            <div className="flex flex-wrap items-center gap-3 font-display text-sm font-bold sm:gap-4">
              <span className="flex items-center gap-2">
                <AppIcon src="/logo.png" />
                {siteConfig.name}
              </span>
              <span className="font-hand text-xl font-normal text-ink-faint">vs</span>
              <span className="flex items-center gap-2">
                <AppIcon src={competitor.icon} />
                {competitor.name}
              </span>
            </div>
            <h1 className="mt-6 font-display text-[clamp(2.4rem,5.5vw,4.2rem)] leading-[0.98] font-extrabold text-balance">
              {article.title}
            </h1>
            <p className="mt-5 text-lg leading-relaxed text-pretty text-ink-soft sm:text-xl">{article.description}</p>
            <p className="mt-6 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-ink-faint">
              <span>
                By the{" "}
                <Link href="/about" className="font-semibold text-ink-soft hover:text-ink">
                  {siteConfig.name} team
                </Link>
              </span>
              <span aria-hidden="true">·</span>
              <span>
                Facts checked <time dateTime={article.updated}>{formatDate(article.updated)}</time>
              </span>
              <span aria-hidden="true">·</span>
              <span>{article.readingMinutes} min read</span>
            </p>
          </div>
          <Illustration name="ill-beaker" size={150} priority className="hidden -rotate-6 lg:block" />
        </div>
      </header>

      <div className="mx-auto grid max-w-6xl gap-12 px-5 pt-10 pb-20 sm:px-8 lg:grid-cols-[minmax(0,1fr)_280px] lg:gap-16">
        <div className="min-w-0 max-w-[44rem]">
          <section aria-labelledby="verdict" className="sticker bg-mint-soft p-6 sm:p-7">
            <h2 id="verdict" className="font-hand text-2xl text-mint-deep">
              The short version
            </h2>
            <div
              className="prose-guide mt-2 !text-[1.1rem] !text-ink"
              dangerouslySetInnerHTML={{ __html: article.verdictHtml }}
            />
          </section>

          <div className="mt-12">
            {article.segments.map((html, i) => (
              <Fragment key={i}>
                <div className="prose-guide" dangerouslySetInnerHTML={{ __html: html }} />
                {i < article.segments.length - 1 && (
                  <InlineCta title={article.cta.title} body={article.cta.body} campaign={`${campaign}-${i + 1}`} />
                )}
              </Fragment>
            ))}
          </div>

          {article.faqHtml.length > 0 && (
            <section aria-labelledby="faq" className="mt-20">
              <h2 id="faq" className="mb-6 font-display text-3xl font-extrabold">
                Frequently asked questions
              </h2>
              <FaqList items={article.faqHtml} />
            </section>
          )}

          <section aria-labelledby="sources" className="mt-16 border-t-2 border-ink/10 pt-8">
            <h2 id="sources" className="font-display text-xl font-bold">
              How we checked
            </h2>
            <p className="mt-3 text-sm leading-relaxed text-ink-soft">
              Everything here about {competitor.name} comes from its App Store listing, its developer&apos;s own pages,
              or the reporting linked below, as of {formatDate(article.updated)}. Prices and features change, and the
              App Store shows different offers to different people, so check the listing before you buy. Spotted
              something out of date? <Link href="/support" className="underline hover:text-ink">Tell us</Link> and
              we&apos;ll fix it.
            </p>
            <ul className="mt-4 space-y-1.5 text-sm">
              {article.sources.map((s) => (
                <li key={s.url}>
                  <a href={s.url} target="_blank" rel="noopener" className="text-ink-soft underline hover:text-ink">
                    {s.label}
                  </a>
                </li>
              ))}
            </ul>
          </section>
        </div>

        <aside className="hidden lg:block">
          <div className="sticky top-24 space-y-8">
            {article.toc.length > 1 && (
              <nav aria-label="On this page">
                <p className="text-xs font-bold tracking-widest text-ink-faint uppercase">On this page</p>
                <ol className="mt-4 space-y-1 border-l-2 border-ink/10 text-sm">
                  {article.toc.map((entry) => (
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
              <p className="mt-3 font-display text-lg leading-tight font-bold">{article.cta.title}</p>
              <a href="#get-app" className="btn-ink mt-4 w-full px-4 py-2.5 text-sm">
                {siteConfig.appStoreUrl ? "Get the app" : "Get early access"}
              </a>
            </div>
          </div>
        </aside>
      </div>
    </article>
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

function Placeholder({ competitor }: { competitor: Competitor }) {
  return (
    <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
      <Breadcrumbs />
      <Illustration name="ill-beaker" size={110} priority className="mt-8 -rotate-6" />
      <h1 className="mt-6 font-display text-[clamp(2.6rem,6vw,4.4rem)] leading-[0.98] font-extrabold">
        {siteConfig.name} vs {competitor.name}
      </h1>
      <p className="mt-6 text-lg leading-relaxed text-ink-soft">{competitor.knownFor}</p>
      <div className="mt-10">
        <TodoBanner title={`Write the ${competitor.name} comparison`}>
          This page is a placeholder and hidden from Google. Write <code>content/compare/{competitor.slug}.md</code>,
          then set <code>ready: true</code> for <code>{competitor.slug}</code> in <code>web/src/lib/comparisons.ts</code>.
        </TodoBanner>
      </div>
      <div className="sticker mt-10 bg-mint-soft p-7">
        <p className="font-hand text-2xl text-mint-deep">coming soon</p>
        <p className="mt-2 text-lg">
          We&apos;re testing both apps side by side on a real iPhone. The full comparison will be here shortly.
        </p>
      </div>
      <div id="get-app" className="sticker mt-10 p-7">
        <p className="font-display text-2xl font-bold">Try {siteConfig.name}</p>
        <div className="mt-5">
          <AppCta campaign={`vs-${competitor.slug}`.slice(0, 40)} />
        </div>
      </div>
    </div>
  );
}
