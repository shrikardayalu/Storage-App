import type { Metadata } from "next";
import Link from "next/link";
import { AppCta } from "@/components/app-cta";
import { ContactLine } from "@/components/contact-line";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: `How the ${siteConfig.name} iPhone app and website handle your information. Photos and files stay on your iPhone. Sharing how you found us is optional.`,
  alternates: { canonical: "/privacy" },
};

// Covers the iOS app and this website. Only the optional acquisition survey
// uses networking. Keep this page, PrivacyInfo.xcprivacy, and App Store Connect's
// App Privacy answers together, and bump siteConfig.legalUpdated.
export default function PrivacyPage() {
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
            Privacy Policy
          </h1>
          <p className="mt-4 text-ink-soft">Last updated {updated}</p>
          <div className="prose-guide mt-10">
            <p>
              <strong>The short version:</strong> the {name} app analyses your photos, videos and files on your
              iPhone and never uploads them. There&apos;s no account, no ads and no tracking. If you choose to share
              how you found us during onboarding, we send that answer to TelemetryDeck for anonymous channel totals.
              You can skip the question. The website collects your email address only if you join the waitlist.
            </p>

            <h2>The {name} app</h2>
            <h3>What the app reads, and where it stays</h3>
            <ul>
              <li>
                <strong>Photos and videos.</strong> With your permission, the app reads your photo library to show what
                takes up space and to find duplicates, blurry shots, screenshots and large videos. If you choose to share
                only some photos, it reads only those. Everything is analysed on your iPhone. Photos, videos and anything learned from them are never uploaded or sent anywhere.
              </li>
              <li>
                <strong>Files.</strong> If you use the Files cleanup, the app reads only the one folder you pick in the
                Files picker: file names, sizes, and when files were last opened or changed. It can&apos;t see anything
                outside that folder.
              </li>
              <li>
                <strong>Free space.</strong> The app reads how much storage your iPhone has free, to show it and to
                measure what each cleanup gave back. These readings are saved on your iPhone only.
              </li>
              <li>
                <strong>Your choices.</strong> Your settings and cleanup choices are saved on your iPhone only.
                Your optional answer about how you found us is also saved locally and, if you choose to share it,
                sent as described below.
              </li>
            </ul>
            <p>
              Deleting the app removes its local settings, readings and choices. It does not remove an anonymous
              survey response already sent to TelemetryDeck; we have no identifier to match that response to you.
            </p>

            <h3>Optional discovery survey</h3>
            <p>
              At the end of onboarding, you can choose where you first heard about {name}. Selecting
              &ldquo;Share &amp; get started&rdquo; sends your selected channel to the analytics service
              TelemetryDeck GmbH. We use response counts to understand how people find us. Selecting
              &ldquo;Skip for now&rdquo; sends no survey response. If you are offline, a shared answer waits on
              your iPhone and is retried when you next open the app.
            </p>
            <p>
              We send only a predefined channel, such as TikTok, Reddit or our website, with the survey event name.
              We do not send your name, email address, account, advertising ID, device ID, photos, file information,
              storage readings or a unique installation identifier. Every response uses the same non-personal
              sender label. TelemetryDeck records when a response arrives and processes ordinary network requests;
              it states that it does not store IP addresses. We do not combine these responses with other data to
              identify you or target ads. Read more in{" "}
              <a href="https://telemetrydeck.com/privacy/">TelemetryDeck&apos;s Privacy Policy</a>.
            </p>

            <h3>What the app changes</h3>
            <p>
              The app changes or deletes only what you approve on a review screen, and iOS asks you to confirm again.
              Deleted photos and videos go to Recently Deleted in the Photos app, where you can recover them for 30
              days. Files deleted with the Files cleanup are removed for good; the app tells you so before you confirm.
            </p>

            <h3>Purchases</h3>
            <p>
              {name} Pro is sold through Apple&apos;s App Store. Apple handles payment, and we never see your name,
              payment details or Apple ID. On your iPhone, the App Store tells the app which Pro plan you own so it can
              unlock Pro. Apple&apos;s handling of your purchase is covered by{" "}
              <a href="https://www.apple.com/legal/privacy/">Apple&apos;s Privacy Policy</a>.
            </p>

            <h3>Other apps</h3>
            <p>
              Some guides open another app for you, such as Photos, Settings or WhatsApp. The app only asks iOS to open
              it; nothing is shared with that app.
            </p>

            <h2>This website</h2>
            <h3>Waitlist</h3>
            <p>
              If you join the waitlist, we store your email address and the page you signed up from. We use it only to
              tell you when {name} launches. We don&apos;t sell or share it, and you can ask us to delete it at any time.
            </p>
            <h3>Hosting</h3>
            <p>
              Like any website, our hosting provider processes basic request information, such as your IP address and
              browser type, to deliver pages and keep the site secure. We don&apos;t use it to identify you.
            </p>
            <h3>Cookies and tracking</h3>
            <p>This website doesn&apos;t set advertising cookies or run third-party ad trackers.</p>

            <h2>Children</h2>
            <p>
              The app collects no personal information from anyone, including children. The waitlist is not meant for
              children under 13, and we&apos;ll delete any address we learn came from one.
            </p>

            <h2>Your rights</h2>
            <p>
              Depending on where you live (for example under the GDPR in the EU and UK, or the CCPA in California), you
              may have the right to see, correct or delete personal information we hold about you, or to object to how
              we use it. The only personal information we hold is a waitlist email address, if you gave us one. We
              don&apos;t sell or share personal information. To make a request, contact us below.
            </p>

            <h2>Changes</h2>
            <p>
              If this policy changes, we&apos;ll update this page and the date at the top.
            </p>

            <h2>Contact</h2>
            <p>
              Questions or requests: <ContactLine subject={`${name} privacy`} />. See also our{" "}
              <Link href="/terms">Terms of Use</Link>.
            </p>
          </div>
          <div id="get-app" className="sticker mt-14 p-7">
            <p className="font-display text-2xl font-bold">Get {name}</p>
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
