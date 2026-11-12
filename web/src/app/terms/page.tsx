import type { Metadata } from "next";
import Link from "next/link";
import { ContactLine } from "@/components/contact-line";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Terms of Use",
  description: `The terms for using the ${siteConfig.name} iPhone app, ${siteConfig.name} Pro subscriptions, and this website.`,
  alternates: { canonical: "/terms" },
};

const EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";

// Linked from the app's paywall and Settings. The subscription section must
// match what the paywall says (Plan.disclosure in the iOS app) and what's in
// App Store Connect. Bump siteConfig.legalUpdated with any change.
export default function TermsPage() {
  const name = siteConfig.name;
  const updated = new Date(`${siteConfig.legalUpdated}T00:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });

  return (
    <>
      <SiteHeader />
      <main id="main" className="flex-1">
        <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
          <p className="eyebrow">legal</p>
          <h1 className="mt-4 font-display text-[clamp(2.6rem,6vw,4rem)] leading-[1] font-extrabold">
            Terms of Use
          </h1>
          <p className="mt-4 text-ink-soft">Last updated {updated}</p>
          <div className="prose-guide mt-10">
            <p>
              These terms cover the {name} iPhone app (&ldquo;the app&rdquo;), {name} Pro, and this website. By using
              them, you agree to these terms.
            </p>

            <h2>1. Apple&apos;s license agreement</h2>
            <p>
              The app is licensed to you under Apple&apos;s{" "}
              <a href={EULA}>Licensed Application End User License Agreement</a> (the &ldquo;Standard EULA&rdquo;).
              These terms add to it. Where the two conflict about the app, the Standard EULA wins.
            </p>

            <h2>2. What the app does</h2>
            <p>
              The app helps you find what takes up space on your iPhone, and remove or shrink the items you choose.
              It works only with what iOS lets it reach: the photos and videos you give it access to, and the one
              folder you pick in Files.
              For space it can&apos;t clear itself, such as other apps&apos; data, it shows you the steps.
            </p>

            <h2>3. You decide what&apos;s deleted</h2>
            <p>
              Nothing is changed or deleted until you approve it on a review screen and confirm with iOS. Suggestions,
              such as duplicates or blurry shots, are only suggestions, so check them before you approve.
            </p>
            <ul>
              <li>
                Deleted photos and videos go to Recently Deleted in Photos, where you can recover them for 30 days
                until you empty it.
              </li>
              <li>
                Shrinking a video or turning a Live Photo into a still replaces the original with a smaller version.
                The original goes to Recently Deleted.
              </li>
              <li>
                <strong>Files deleted with the Files cleanup are deleted for good</strong> and can&apos;t be recovered.
              </li>
            </ul>
            <p>
              Keep a backup of anything you can&apos;t lose, for example in iCloud Photos or on a computer. Figures for
              space you could free are estimates; the free space iOS reports is the real measure.
            </p>

            <h2>4. {name} Pro</h2>
            <p>
              Scanning, deleting, duplicates and junk, the Files cleanup and the guides are free. {name} Pro unlocks
              shrinking videos, trimming them, turning Live Photos into stills, and keeping the best shot of each
              burst. Pro is sold as:
            </p>
            <ul>
              <li>
                <strong>Pro Weekly and Pro Annual</strong>, auto-renewing subscriptions. Payment is charged to your
                Apple ID when you confirm the purchase. Each subscription renews automatically at the same price and
                length unless you cancel at least 24 hours before the end of the current period. Your account is
                charged for the renewal within 24 hours before the period ends.
              </li>
              <li>
                <strong>Pro Lifetime</strong>, a one-time purchase that doesn&apos;t renew.
              </li>
            </ul>
            <p>
              Prices are shown in the app before you buy, in your local currency. You can manage or cancel a
              subscription at any time in <strong>Settings &rarr; your name &rarr; Subscriptions</strong> on your
              iPhone. Cancelling stops the next renewal; Pro stays on until the end of the period you&apos;ve paid for.
              Buying Lifetime doesn&apos;t cancel a subscription you already have, so cancel it there too.
            </p>
            <p>
              Purchases are handled by Apple, so refunds are too. Request one at{" "}
              <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>. To use Pro on a new or reset
              iPhone with the same Apple ID, tap <strong>Restore Purchases</strong> in the app.
            </p>
            <p>
              If we change a subscription&apos;s price, Apple tells you first and, where required, asks you to agree.
              What you&apos;ve already shrunk or converted stays that way if Pro ends.
            </p>

            <h2>5. Using the app and site fairly</h2>
            <p>
              Don&apos;t misuse the app or this website. For example, don&apos;t try to break, copy, reverse-engineer
              or resell them, except where the law allows. The app, its design and this website&apos;s content belong
              to {name}. iPhone, iOS, iCloud and Photos are trademarks of Apple Inc.; {name} is not affiliated with
              Apple. Other apps mentioned in our guides, such as WhatsApp, belong to their owners.
            </p>

            <h2>6. No guarantees</h2>
            <p>
              We work hard to make the app safe and accurate, but it&apos;s provided &ldquo;as is&rdquo; and &ldquo;as
              available&rdquo;. To the extent the law allows, we don&apos;t promise that it will be error-free or free
              any particular amount of space. Our guides describe iOS and other apps as they worked when we checked
              them, and Apple or other developers may change them.
            </p>

            <h2>7. Limits on liability</h2>
            <p>
              To the extent the law allows, {name} isn&apos;t liable for indirect or consequential losses, or for the
              loss of content you chose to delete or replace. Our total liability for any claim about the app is
              limited to the amount you paid for {name} Pro in the 12 months before the claim. Nothing in these terms
              limits rights you have under consumer law that can&apos;t be limited.
            </p>

            <h2>8. Apple</h2>
            <p>
              These terms are between you and {name}, not Apple. Apple isn&apos;t responsible for the app, its
              content, maintenance or support, or for any claims about it, except as set out in the Standard EULA.
              Apple and its subsidiaries are third-party beneficiaries of these terms and may enforce them against
              you.
            </p>

            <h2>9. Changes</h2>
            <p>
              We may update these terms. When we do, we&apos;ll change the date at the top. If you keep using the app
              or site after a change, the new terms apply.
            </p>

            <h2>10. Contact</h2>
            <p>
              Questions about these terms: <ContactLine subject={`${name} terms`} />. See also our{" "}
              <Link href="/privacy">Privacy Policy</Link> and <Link href="/support">Support</Link>.
            </p>
          </div>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
