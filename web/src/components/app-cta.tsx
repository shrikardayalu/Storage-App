import { WaitlistForm } from "@/components/waitlist-form";
import { appStoreLink } from "@/lib/site";

/**
 * The one conversion action, wherever it appears. Before launch it's the
 * waitlist; once NEXT_PUBLIC_APP_STORE_URL is set, every CTA on the site
 * becomes an App Store link tagged with `campaign` for install attribution.
 */
export function AppCta({
  campaign,
  tone = "light",
  label,
}: {
  campaign: string;
  tone?: "light" | "dark";
  label?: string;
}) {
  const href = appStoreLink(campaign);

  if (!href) return <WaitlistForm source={campaign} tone={tone} buttonLabel={label} />;

  return (
    <div>
      <a
        href={href}
        data-cta={campaign}
        className={`btn-ink px-6 py-3.5 text-base ${tone === "dark" ? "bg-on-band text-band" : ""}`}
      >
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="currentColor">
          <path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.3 1.2 9.7.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.5-1-2.5-3.8zM14 5.5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1.1.1 2.1-.6 2.8-1.4z" />
        </svg>
        {label ?? "Download free on the App Store"}
      </a>
      <p className={`mt-2.5 pl-1 text-sm ${tone === "dark" ? "text-on-band/70" : "text-ink-faint"}`}>
        Free to start. Requires iOS 17 or later.
      </p>
    </div>
  );
}
