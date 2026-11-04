import Link from "next/link";
import { Illustration } from "@/components/ink";
import { getAllGuides } from "@/lib/guides";
import { siteConfig } from "@/lib/site";
import { topics } from "@/lib/topics";

const PER_TOPIC = 5;

// Sitewide links to every topic's guides: each page passes a little authority
// to the library, and crawlers reach any guide in two hops from anywhere.
export function SiteFooter() {
  const guides = getAllGuides();
  const year = new Date(guides[0]?.updated ?? "2026-01-01").getFullYear();

  return (
    <footer className="relative mt-auto overflow-hidden border-t-2 border-ink bg-ink text-paper">
      <div className="mx-auto max-w-6xl px-5 pt-16 pb-10 sm:px-8">
        <div className="grid gap-12 md:grid-cols-[1.2fr_2fr]">
          <div>
            <p className="font-display text-2xl font-bold">{siteConfig.name}</p>
            <p className="mt-3 max-w-xs text-paper/65">{siteConfig.description}</p>
            <p className="font-hand mt-6 text-xl text-mint">made for people with full phones ♥</p>
          </div>

          <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-3">
            {topics.map((topic) => {
              const inTopic = guides.filter((g) => g.topic === topic.id).slice(0, PER_TOPIC);
              if (!inTopic.length) return null;
              return (
                <div key={topic.id}>
                  <p className="text-sm font-semibold tracking-wide text-mint uppercase">{topic.name}</p>
                  <ul className="mt-4 space-y-2.5 text-[0.95rem] text-paper/75">
                    {inTopic.map((g) => (
                      <li key={g.slug}>
                        <Link href={`/guides/${g.slug}`} className="transition-colors hover:text-paper">
                          {g.title}
                        </Link>
                      </li>
                    ))}
                  </ul>
                </div>
              );
            })}
            <div>
              <p className="text-sm font-semibold tracking-wide text-mint uppercase">{siteConfig.name}</p>
              <ul className="mt-4 space-y-2.5 text-[0.95rem] text-paper/75">
                <li>
                  <Link href="/guides" className="hover:text-paper">
                    All guides
                  </Link>
                </li>
                <li>
                  <Link href="/pricing" className="hover:text-paper">
                    Pricing
                  </Link>
                </li>
                <li>
                  <Link href="/about" className="hover:text-paper">
                    About
                  </Link>
                </li>
                <li>
                  <Link href="/support" className="hover:text-paper">
                    Support
                  </Link>
                </li>
                <li>
                  <Link href="/privacy" className="hover:text-paper">
                    Privacy
                  </Link>
                </li>
                <li>
                  <Link href="/terms" className="hover:text-paper">
                    Terms
                  </Link>
                </li>
                <li>
                  <a href="/guides/feed.xml" className="hover:text-paper">
                    RSS
                  </a>
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div className="mt-16 flex flex-col gap-2 border-t border-paper/15 pt-6 text-sm text-paper/50 sm:flex-row sm:justify-between">
          <p>
            © {year} {siteConfig.name}. Not affiliated with Apple Inc.
          </p>
          <p>iPhone and iOS are trademarks of Apple Inc.</p>
        </div>
      </div>
      <Illustration
        name="ill-piggy"
        size={180}
        className="pointer-events-none absolute -right-8 -bottom-10 rotate-12 opacity-15 grayscale invert"
      />
    </footer>
  );
}
