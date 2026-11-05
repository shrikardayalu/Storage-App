import type { ReactNode } from "react";

// A loud "still to do" note for the site owner, shown on the live site until
// launch. Set NEXT_PUBLIC_HIDE_TODO_BANNERS=1 (in Vercel → Settings →
// Environment Variables) to hide every one of them at once.

export const showTodoBanners = process.env.NEXT_PUBLIC_HIDE_TODO_BANNERS !== "1";

export function TodoBanner({ title, children }: { title: string; children: ReactNode }) {
  if (!showTodoBanners) return null;
  return (
    <div
      role="note"
      aria-label="Note for the site owner"
      // Fixed colors, so it reads the same in light and dark mode.
      className="relative overflow-hidden rounded-2xl border-2 border-dashed border-[#1a1a17] bg-[repeating-linear-gradient(-45deg,#fde68a_0,#fde68a_14px,#fef3c7_14px,#fef3c7_28px)] p-5 text-[#1a1a17] shadow-[4px_4px_0_0_#1a1a17] sm:p-6"
    >
      <p className="font-hand text-xl leading-none">to do before launch</p>
      <p className="mt-2 font-display text-2xl leading-tight font-extrabold">{title}</p>
      <div className="mt-2 max-w-3xl text-base leading-relaxed">{children}</div>
    </div>
  );
}
