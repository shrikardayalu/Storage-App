"use client";

import { useEffect, useState } from "react";

const COLORS = { light: "#F4F1EA", dark: "#121211" } as const;
type Theme = keyof typeof COLORS;

function currentTheme(): Theme {
  return document.documentElement.dataset.theme === "dark" ? "dark" : "light";
}

function apply(theme: Theme) {
  document.documentElement.dataset.theme = theme;
  // Browser chrome (mobile address bar) follows the page, not the system.
  for (const meta of document.querySelectorAll('meta[name="theme-color"]')) {
    meta.removeAttribute("media");
    meta.setAttribute("content", COLORS[theme]);
  }
}

/**
 * Light/dark switch. The first visit defaults to light mode (the inline
 * script in layout.tsx sets data-theme before paint); a click saves the choice.
 * Icons are swapped in CSS so the server and client markup always match.
 */
export function ThemeToggle({ className }: { className?: string }) {
  const [theme, setTheme] = useState<Theme | null>(null);

  useEffect(() => {
    const t = currentTheme();
    // Reads the attribute the inline script set, which only exists client-side.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setTheme(t);
    apply(t);
  }, []);

  function toggle() {
    const next: Theme = currentTheme() === "dark" ? "light" : "dark";
    apply(next);
    setTheme(next);
    try {
      localStorage.setItem("theme", next);
    } catch {
      // Private mode: the choice just lasts for this visit.
    }
  }

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
      className={`theme-toggle grid size-10 place-items-center rounded-full text-ink-soft transition-colors hover:bg-ink/5 hover:text-ink ${className ?? ""}`}
    >
      <svg className="icon-moon" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5a8.5 8.5 0 1 0 10.7 10.7Z" />
      </svg>
      <svg className="icon-sun" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4" />
      </svg>
    </button>
  );
}
