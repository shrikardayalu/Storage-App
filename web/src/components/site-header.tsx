import Link from "next/link";
import { siteConfig } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="border-b border-slate-200/70">
      <nav
        aria-label="Main"
        className="mx-auto flex h-16 max-w-5xl items-center justify-between px-5 sm:px-8"
      >
        <Link
          href="/"
          className="flex items-center gap-2 font-semibold tracking-tight text-slate-900"
        >
          <span
            aria-hidden="true"
            className="grid size-7 place-items-center rounded-lg bg-teal-600 text-xs font-bold text-white"
          >
            S
          </span>
          {siteConfig.name}
        </Link>
        <span className="rounded-full border border-slate-200 px-3 py-1 text-xs font-medium text-slate-600">
          Coming soon
        </span>
      </nav>
    </header>
  );
}
