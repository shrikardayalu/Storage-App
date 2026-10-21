import type { CSSProperties } from "react";
import Link from "next/link";
import { Illustration } from "@/components/ink";
import type { GuideMeta } from "@/lib/guides";
import { getTopic } from "@/lib/topics";

const tilts = [-1.2, 0.8, -0.5, 1.1, -0.9, 0.6];

/** Index card with a folder tab naming its topic. */
export function GuideCard({ guide, index = 0 }: { guide: GuideMeta; index?: number }) {
  const topic = getTopic(guide.topic);
  const rest = tilts[index % tilts.length];

  return (
    <article
      data-reveal="tilt"
      style={{ "--tilt": rest * 3, "--rest": rest, "--reveal-delay": (index % 3) * 90 } as CSSProperties}
      className="group relative pt-5"
    >
      <span className="absolute top-0 left-5 rounded-t-xl border-2 border-b-0 border-ink bg-mint px-3 pt-1 pb-2 text-xs font-bold tracking-wide uppercase">
        {topic?.name}
      </span>
      <div className="sticker sticker-lift flex h-full flex-col p-6">
        <Illustration
          name={guide.illustration}
          size={64}
          className="absolute -top-5 right-4 transition-transform duration-500 ease-[var(--ease-spring)] group-hover:-translate-y-1 group-hover:rotate-6"
        />
        <h3 className="mt-2 pr-12 font-display text-xl leading-tight font-bold">
          <Link href={`/guides/${guide.slug}`} className="after:absolute after:inset-0 after:content-['']">
            {guide.title}
          </Link>
        </h3>
        <p className="mt-3 line-clamp-3 text-[0.95rem] leading-relaxed text-ink-soft">{guide.description}</p>
        <p className="mt-auto flex items-center justify-between pt-6 text-sm font-semibold">
          <span className="text-ink-faint">{guide.readingMinutes} min read</span>
          <span className="flex items-center gap-1 transition-transform group-hover:translate-x-1">
            Read guide <span aria-hidden="true">→</span>
          </span>
        </p>
      </div>
    </article>
  );
}
