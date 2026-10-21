import Link from "next/link";
import { Illustration } from "@/components/ink";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export default function NotFound() {
  return (
    <>
      <SiteHeader />
      <main id="main" className="flex flex-1 flex-col items-center justify-center px-5 py-24 text-center">
        <Illustration name="ill-empty-box" size={140} priority />
        <h1 className="mt-6 font-display text-5xl font-extrabold">Nothing here.</h1>
        <p className="font-hand mt-3 text-2xl text-ink-soft">(at least it&apos;s not taking up space)</p>
        <div className="mt-8 flex gap-3">
          <Link href="/" className="btn-ink px-5 py-3 text-sm">
            Home
          </Link>
          <Link href="/guides" className="rounded-full border-2 border-ink px-5 py-3 text-sm font-semibold">
            Guides
          </Link>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
