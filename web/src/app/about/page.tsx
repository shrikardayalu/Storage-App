import type { Metadata } from "next";
import Link from "next/link";
import { AppCta } from "@/components/app-cta";
import { Illustration } from "@/components/ink";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "About",
  description: `Who makes ${siteConfig.name}, and how we write and check our iPhone storage guides.`,
  alternates: { canonical: "/about" },
};

// E-E-A-T: say who is behind the site and how the guides are made and checked.
export default function AboutPage() {
  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1">
        <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
          <Illustration name="ill-phone-sparkle" size={110} priority className="-rotate-6" />
          <h1 className="mt-6 font-display text-[clamp(2.6rem,6vw,4.4rem)] leading-[0.98] font-extrabold">
            We&apos;re building the storage app we wanted.
          </h1>
          <div className="prose-guide mt-10">
            <p>
              {siteConfig.name} is a small, independent team making an iPhone utility that finds the photos,
              screenshots, and videos filling up your phone and lets you decide what to remove or compress.
            </p>
            <h2>How we write our guides</h2>
            <ul>
              <li>
                <strong>Answer first.</strong> Every guide starts with a short, direct answer, then the steps.
              </li>
              <li>
                <strong>Built-in tools before our app.</strong> If Settings or Photos can solve it, we show you
                how. We mention {siteConfig.name} only where it genuinely saves time.
              </li>
              <li>
                <strong>Checked on a real iPhone.</strong> Menu paths are tested on current iOS and updated when
                Apple moves things. Each guide shows the date it was last reviewed.
              </li>
              <li>
                <strong>No scare tactics.</strong> We won&apos;t claim an app can do what iOS doesn&apos;t allow,
                like clearing System Data or other apps&apos; caches.
              </li>
            </ul>
            <p>
              Spotted something out of date? We&apos;d like to fix it. Start with our{" "}
              <Link href="/guides">guides library</Link>.
            </p>
          </div>
          <div id="get-app" className="sticker mt-14 p-7">
            <p className="font-display text-2xl font-bold">Try {siteConfig.name}</p>
            <div className="mt-5">
              <AppCta campaign="about" />
            </div>
          </div>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
