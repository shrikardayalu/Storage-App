import type { Metadata } from "next";
import Link from "next/link";
import { ContactLine } from "@/components/contact-line";
import { FaqList } from "@/components/faq-list";
import { JsonLd } from "@/components/json-ld";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { markdownToHtml } from "@/lib/guides";
import { faqSchema, graph } from "@/lib/schema";
import { siteConfig } from "@/lib/site";

const name = siteConfig.name;

export const metadata: Metadata = {
  title: "Support",
  description: `Help with ${name}: restoring and cancelling Pro, refunds, Photos access, and why space comes back only after you empty Recently Deleted.`,
  alternates: { canonical: "/support" },
};

// The App Store Connect "Support URL". Answers must match the app's behaviour.
const faq = [
  {
    q: "How do I restore Pro on a new iPhone?",
    a: `Sign in with the Apple ID you bought Pro with, then open ${name} and go to **Settings → Pro → Restore Purchases**. Restore is also on the upgrade screen.`,
  },
  {
    q: "How do I cancel my subscription?",
    a: `On your iPhone, open **Settings → your name → Subscriptions**, tap ${name}, then **Cancel Subscription**. You can also get there from **${name} → Settings → Manage Subscription**. Cancel at least 24 hours before the period ends to avoid the next renewal. Pro stays on until the end of the period you've paid for.`,
  },
  {
    q: "I bought Lifetime. Do I need to cancel my subscription?",
    a: "Yes. Buying Lifetime doesn't cancel a weekly or annual subscription you already had. Cancel it as above so you aren't charged again. Pro stays on either way.",
  },
  {
    q: "Can I get a refund?",
    a: "Purchases are handled by Apple, so refunds are too. Request one at [reportaproblem.apple.com](https://reportaproblem.apple.com).",
  },
  {
    q: `Why doesn't ${name} see my photos?`,
    a: `During Test Mode, ${name} reads only an album named **Storage App Test**. Create it in the Photos app (**Albums → + → New Album**), add some photos and videos, then tap **Scan** in ${name}. If Photos access is off, turn it on in **Settings → Apps → ${name} → Photos**. Cleanups need **Full Access**.`,
  },
  {
    q: "I deleted photos but my free space didn't go up.",
    a: `iOS keeps deleted photos and videos in **Recently Deleted** for 30 days, and they still take up space until it's emptied. ${name} can't empty it for you, but it walks you through it and measures the space that comes back. Open it from Home ("waiting in Recently Deleted").`,
  },
  {
    q: "Can I undo a cleanup?",
    a: "Photos and videos can be recovered from **Recently Deleted** in the Photos app for 30 days. Files deleted with the Files cleanup are deleted for good, and the app says so before you confirm.",
  },
  {
    q: `Does ${name} upload my photos?`,
    a: `No. Everything is analysed on your iPhone, and the app has no account and collects no data. See our [Privacy Policy](/privacy).`,
  },
];

export default function SupportPage() {
  const items = faq.map((item) => ({ q: item.q, a: markdownToHtml(item.a) }));

  return (
    <>
      <JsonLd data={graph(faqSchema(faq))} />
      <SiteHeader />
      <main id="main" className="flex-1">
        <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
          <p className="eyebrow">support</p>
          <h1 className="mt-4 font-display text-[clamp(2.6rem,6vw,4rem)] leading-[1] font-extrabold">
            How can we help?
          </h1>
          <p className="mt-6 text-lg text-ink-soft">
            Answers to the common questions about {name} and {name} Pro.
          </p>
          <div className="mt-12">
            <FaqList items={items} />
          </div>
          <div className="prose-guide mt-14">
            <h2>Still stuck?</h2>
            {siteConfig.supportEmail ? (
              <p>
                Email <ContactLine subject={`${name} support`} />. Tell us your iPhone model, iOS version and what
                happened, and we&apos;ll get back to you.
              </p>
            ) : (
              <p>
                Our support inbox isn&apos;t open yet. In the meantime, our <Link href="/guides">guides</Link> cover
                most iPhone storage questions.
              </p>
            )}
            <p>
              See also our <Link href="/privacy">Privacy Policy</Link> and <Link href="/terms">Terms of Use</Link>.
            </p>
          </div>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
