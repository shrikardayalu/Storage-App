import Image from "next/image";
import Link from "next/link";
import { siteConfig } from "@/lib/site";

const nav = [
  { href: "/#how-it-works", label: "How it works" },
  { href: "/#compare", label: "Compare" },
  { href: "/guides", label: "Guides" },
  { href: "/pricing", label: "Pricing" },
  { href: "/#faq", label: "FAQ" },
];

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-hairline bg-paper/75 backdrop-blur-xl backdrop-saturate-150">
      <nav aria-label="Main" className="mx-auto flex h-16 max-w-6xl items-center gap-6 px-5 sm:px-8">
        <Link href="/" className="group flex items-center gap-2.5 font-display text-[1.05rem] font-bold">
          <Image
            src="/logo.png"
            alt=""
            width={34}
            height={34}
            priority
            className="rounded-[9px] border-[1.5px] border-ink transition-transform duration-500 ease-[var(--ease-spring)] group-hover:-rotate-6"
          />
          {siteConfig.name}
        </Link>

        <ul className="ml-auto hidden items-center gap-1 text-[0.95rem] font-medium text-ink-soft md:flex">
          {nav.map((item) => (
            <li key={item.href}>
              <Link
                href={item.href}
                className="rounded-full px-3.5 py-2 transition-colors hover:bg-ink/5 hover:text-ink"
              >
                {item.label}
              </Link>
            </li>
          ))}
        </ul>

        <a href="#get-app" className="btn-ink ml-auto px-4 py-2 text-sm md:ml-2">
          {siteConfig.appStoreUrl ? "Get the app" : "Get early access"}
        </a>
      </nav>
    </header>
  );
}
