import type { Metadata } from "next";
import { AppCta } from "@/components/app-cta";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy",
  description: `How the ${siteConfig.name} website handles your information.`,
  alternates: { canonical: "/privacy" },
};

// Covers the website only. Add the app's own policy before it ships, and have
// both reviewed.
export default function PrivacyPage() {
  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1">
        <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
          <h1 className="font-display text-[clamp(2.6rem,6vw,4rem)] leading-[1] font-extrabold">Privacy</h1>
          <div className="prose-guide mt-10">
            <p>This page explains what this website collects. It&apos;s short because we collect very little.</p>
            <h2>Waitlist</h2>
            <p>
              If you join the waitlist, we store your email address and the page you signed up from. We use it
              only to tell you when {siteConfig.name} launches. We don&apos;t sell or share it, and you can ask us
              to delete it at any time.
            </p>
            <h2>Cookies and tracking</h2>
            <p>This website doesn&apos;t set advertising cookies or run third-party ad trackers.</p>
            <h2>Changes</h2>
            <p>If this policy changes, we&apos;ll update this page.</p>
          </div>
          <div id="get-app" className="sticker mt-14 p-7">
            <p className="font-display text-2xl font-bold">Get {siteConfig.name}</p>
            <div className="mt-5">
              <AppCta campaign="privacy" />
            </div>
          </div>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
