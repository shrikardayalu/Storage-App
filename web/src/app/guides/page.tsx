import type { Metadata } from "next";
import { AppCta } from "@/components/app-cta";
import { GuideCard } from "@/components/guide-card";
import { Illustration, Scribble } from "@/components/ink";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { getAllGuides } from "@/lib/guides";
import { breadcrumbSchema, graph } from "@/lib/schema";
import { absoluteUrl, siteConfig } from "@/lib/site";
import { topics } from "@/lib/topics";

export const metadata: Metadata = {
  title: "iPhone Storage Guides",
  description:
    "Plain-English guides to freeing up iPhone storage: what fills your phone, how to clear photos, screenshots, and videos safely, and which fixes actually work.",
  alternates: { canonical: "/guides" },
};

export default function GuidesPage() {
  const guides = getAllGuides();
  const groups = topics
    .map((topic) => ({ topic, guides: guides.filter((g) => g.topic === topic.id) }))
    .filter((group) => group.guides.length > 0);

  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1 overflow-x-clip">
        <section className="mx-auto max-w-6xl px-5 pt-16 pb-12 sm:px-8 sm:pt-24">
          <div className="grid items-end gap-10 lg:grid-cols-[1fr_auto]">
            <div className="max-w-3xl">
              <p className="eyebrow">the library</p>
              <h1 className="mt-3 font-display text-[clamp(2.8rem,6.5vw,5.2rem)] leading-[0.95] font-extrabold">
                iPhone storage,{" "}
                <span className="relative inline-block">
                  explained.
                  <Scribble className="absolute -bottom-2 left-0 h-3.5 w-full text-mint" />
                </span>
              </h1>
              <p className="mt-7 max-w-xl text-lg leading-relaxed text-ink-soft sm:text-xl">
                Straight answers to the questions people actually search, using the tools already on your
                iPhone. Every guide starts with the short answer.
              </p>
            </div>
            <Illustration name="ill-stack-large" size={160} priority className="hidden rotate-6 lg:block" />
          </div>

          <nav aria-label="Topics" className="mt-12 flex flex-wrap gap-2.5">
            {groups.map(({ topic, guides: inTopic }) => (
              <a
                key={topic.id}
                href={`#${topic.id}`}
                className="rounded-full border-2 border-ink bg-surface px-4 py-2 text-sm font-semibold transition-all hover:-translate-y-0.5 hover:bg-mint hover:shadow-[3px_3px_0_var(--ink)]"
              >
                {topic.name} <span className="text-ink-faint">· {inTopic.length}</span>
              </a>
            ))}
          </nav>
        </section>

        {groups.map(({ topic, guides: inTopic }, gi) => (
          <section
            key={topic.id}
            id={topic.id}
            aria-labelledby={`${topic.id}-heading`}
            className={gi % 2 ? "border-y-2 border-ink bg-surface" : ""}
          >
            <div className="mx-auto max-w-6xl px-5 py-20 sm:px-8">
              <div className="flex items-center gap-5" data-reveal>
                <Illustration name={topic.illustration} size={72} />
                <div>
                  <h2 id={`${topic.id}-heading`} className="font-display text-3xl font-extrabold sm:text-4xl">
                    {topic.name}
                  </h2>
                  <p className="mt-1 text-ink-soft">{topic.blurb}</p>
                </div>
              </div>
              <div className="mt-12 grid gap-x-6 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
                {inTopic.map((guide, i) => (
                  <GuideCard key={guide.slug} guide={guide} index={i} />
                ))}
              </div>
            </div>
          </section>
        ))}

        <section id="get-app" className="mx-auto max-w-6xl px-5 py-24 sm:px-8">
          <div className="misprint rounded-[32px]" data-reveal>
            <div className="rounded-[32px] border-[2.5px] border-ink bg-surface px-7 py-14 sm:px-12">
              <h2 className="max-w-xl font-display text-[clamp(2rem,4.5vw,3.2rem)] leading-[1] font-extrabold">
                Rather skip the homework?
              </h2>
              <p className="mt-4 max-w-lg text-lg text-ink-soft">
                {siteConfig.name} shrinks your videos, photos, and screenshots instead of deleting them. You confirm every change.
              </p>
              <div className="mt-8">
                <AppCta campaign="guides-hub" />
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
            name: `${siteConfig.name} Guides`,
            url: absoluteUrl("/guides"),
            mainEntity: {
              "@type": "ItemList",
              itemListElement: guides.map((g, i) => ({
                "@type": "ListItem",
                position: i + 1,
                url: absoluteUrl(`/guides/${g.slug}`),
                name: g.title,
              })),
            },
          },
          breadcrumbSchema([
            { name: "Home", path: "/" },
            { name: "Guides", path: "/guides" },
          ]),
        )}
      />
    </>
  );
}
