"use client";

import { useEffect, useRef } from "react";

/**
 * Fixed mint bar at the very top of the viewport. Width grows left → right as
 * the reader scrolls through the article. z-index sits above the paper grain.
 */
export function ReadingProgress() {
  const barRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const bar = barRef.current;
    const track = trackRef.current;
    if (!bar || !track) return;

    let frame = 0;
    const update = () => {
      const article = document.querySelector("main article");
      let progress = 0;

      if (article instanceof HTMLElement) {
        const rect = article.getBoundingClientRect();
        const scrolled = -rect.top;
        const total = article.offsetHeight - window.innerHeight;
        progress = total > 0 ? Math.min(1, Math.max(0, scrolled / total)) : scrolled > 0 ? 1 : 0;
      } else {
        const max = document.documentElement.scrollHeight - window.innerHeight;
        progress = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      }

      bar.style.width = `${progress * 100}%`;
      track.setAttribute("aria-valuenow", String(Math.round(progress * 100)));
    };

    const onScroll = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(update);
    };

    update();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, []);

  return (
    <div
      ref={trackRef}
      role="progressbar"
      aria-label="Reading progress"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={0}
      className="pointer-events-none fixed inset-x-0 top-0 z-[110] h-1.5 bg-ink/15"
    >
      <div
        ref={barRef}
        className="h-full w-0 transition-[width] duration-75 ease-out"
        style={{ backgroundColor: "#71d19a" }}
      />
    </div>
  );
}
