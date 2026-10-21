"use client";

import { useEffect, useState } from "react";

/**
 * Phone-only bar that slides up once a reader is a third of the way into a
 * guide, where many readers stop, and hides near the page's own end CTA.
 */
export function StickyCta({ label }: { label: string }) {
  const [visible, setVisible] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    const target = document.getElementById("get-app");
    const onScroll = () => {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const progress = max > 0 ? window.scrollY / max : 0;
      const nearEnd = target ? target.getBoundingClientRect().top < window.innerHeight : false;
      setVisible(progress > 0.33 && !nearEnd);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  if (dismissed) return null;

  return (
    <div
      className={`fixed inset-x-3 bottom-3 z-40 transition-all duration-500 ease-[var(--ease-spring)] md:hidden ${
        visible ? "translate-y-0 opacity-100" : "pointer-events-none translate-y-[130%] opacity-0"
      }`}
    >
      <div className="flex items-center gap-3 rounded-full border-2 border-ink bg-surface p-1.5 pl-5 shadow-[4px_5px_0_var(--ink)]">
        <p className="flex-1 text-sm leading-tight font-semibold">{label}</p>
        <a href="#get-app" className="btn-ink px-4 py-2.5 text-sm">
          Get it
        </a>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          aria-label="Dismiss"
          className="grid size-8 place-items-center rounded-full text-ink-faint hover:text-ink"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
