// Native <details> so answers are in the HTML for crawlers and work without JS.
// Answers are trusted HTML rendered from our own Markdown.

export function FaqList({ items }: { items: { q: string; a: string }[] }) {
  return (
    <div className="divide-y-2 divide-ink/10 border-y-2 border-ink">
      {items.map((item) => (
        <details key={item.q} className="group py-1 [&_summary::-webkit-details-marker]:hidden">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 font-display text-lg font-bold tracking-tight sm:text-xl">
            <h3>{item.q}</h3>
            <span
              aria-hidden="true"
              className="grid size-9 shrink-0 place-items-center rounded-full border-2 border-ink text-xl transition-all duration-300 group-open:rotate-45 group-open:bg-mint"
            >
              +
            </span>
          </summary>
          <div
            className="prose-guide max-w-2xl pr-12 pb-6 !text-base"
            dangerouslySetInnerHTML={{ __html: item.a }}
          />
        </details>
      ))}
    </div>
  );
}
