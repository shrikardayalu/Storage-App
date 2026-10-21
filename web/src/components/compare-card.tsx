import type { CSSProperties } from "react";
import Link from "next/link";
import { compareHref, type Competitor } from "@/lib/comparisons";
import { siteConfig } from "@/lib/site";

const tilts = [0.8, -1.1, 0.5, -0.7, 1, -0.4];

/** "Us vs. them" card. The whole card links to the comparison article. */
export function CompareCard({ competitor, index = 0 }: { competitor: Competitor; index?: number }) {
  const rest = tilts[index % tilts.length];

  return (
    <article
      data-reveal="tilt"
      style={{ "--tilt": rest * 3, "--rest": rest, "--reveal-delay": (index % 3) * 90 } as CSSProperties}
      className="group relative"
    >
      <div className="sticker sticker-lift flex h-full flex-col p-6">
        <div className="flex items-center gap-3 font-display text-lg font-bold">
          <span className="rounded-full border-2 border-ink bg-mint px-3 py-1 text-sm">{siteConfig.name}</span>
          <span className="font-hand text-xl font-normal text-ink-faint">vs</span>
          <span
            aria-hidden="true"
            className="grid size-9 place-items-center rounded-[10px] border-2 border-ink bg-paper-deep text-base"
          >
            {competitor.name.charAt(0)}
          </span>
        </div>

        <h3 className="mt-5 font-display text-2xl leading-tight font-bold">
          <Link href={compareHref(competitor.slug)} className="after:absolute after:inset-0 after:content-['']">
            {competitor.name}
          </Link>
        </h3>
        {competitor.maker && <p className="text-sm text-ink-faint">by {competitor.maker}</p>}
        <p className="mt-3 text-[0.95rem] leading-relaxed text-ink-soft">{competitor.knownFor}</p>

        <ul className="mt-5 flex flex-wrap gap-2">
          {competitor.tags.map((tag) => (
            <li key={tag} className="rounded-full border border-ink/20 px-2.5 py-0.5 text-xs font-medium text-ink-soft">
              {tag}
            </li>
          ))}
        </ul>

        <p className="mt-auto flex items-center justify-between pt-6 text-sm font-semibold">
          <span className="text-ink-faint">{competitor.ready ? "Side-by-side" : "Comparison coming soon"}</span>
          <span className="flex items-center gap-1 transition-transform group-hover:translate-x-1">
            Compare <span aria-hidden="true">→</span>
          </span>
        </p>
      </div>
    </article>
  );
}
