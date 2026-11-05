import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { AppCta } from "@/components/app-cta";
import { CompareCard } from "@/components/compare-card";
import { TodoBanner } from "@/components/todo-banner";
import { Illustration } from "@/components/ink";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { competitors, getCompetitor } from "@/lib/comparisons";
import { siteConfig } from "@/lib/site";

export const instant = false;

export function generateStaticParams() {
  return competitors.map((c) => ({ slug: c.slug }));
}

export async function generateMetadata({ params }: PageProps<"/compare/[slug]">): Promise<Metadata> {
  const { slug } = await params;
  const competitor = getCompetitor(slug);
  if (!competitor) return {};

  const title = `${siteConfig.name} vs ${competitor.name}`;
  return {
    title,
    description: `How ${siteConfig.name} compares with ${competitor.name} for freeing up iPhone storage.`,
    alternates: { canonical: `/compare/${competitor.slug}` },
    // Placeholders shouldn't be indexed until the article is written.
    robots: competitor.ready ? undefined : { index: false, follow: true },
  };
}

// Placeholder until the comparison articles are written.
export default async function ComparePage({ params }: PageProps<"/compare/[slug]">) {
  const { slug } = await params;
  const competitor = getCompetitor(slug);
  if (!competitor) notFound();

  const others = competitors.filter((c) => c.slug !== competitor.slug).slice(0, 3);

  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1 overflow-x-clip">
        <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
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
          <Illustration name="ill-beaker" size={110} priority className="mt-8 -rotate-6" />
          <h1 className="mt-6 font-display text-[clamp(2.6rem,6vw,4.4rem)] leading-[0.98] font-extrabold">
            {siteConfig.name} vs {competitor.name}
          </h1>
          <p className="mt-6 text-lg leading-relaxed text-ink-soft">{competitor.knownFor}</p>
          {!competitor.ready && (
            <div className="mt-10">
              <TodoBanner title={`Write the ${competitor.name} comparison`}>
                This page is a placeholder and hidden from Google. Write the article, then set{" "}
                <code>ready: true</code> for <code>{competitor.slug}</code> in <code>web/src/lib/comparisons.ts</code>.
              </TodoBanner>
            </div>
          )}
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
      </main>
      <SiteFooter />
    </>
  );
}
