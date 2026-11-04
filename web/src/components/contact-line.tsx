import Link from "next/link";
import { siteConfig } from "@/lib/site";

/** How to reach a person: the support email when it's set, otherwise the support page. */
export function ContactLine({ subject }: { subject: string }) {
  if (siteConfig.supportEmail) {
    const href = `mailto:${siteConfig.supportEmail}?subject=${encodeURIComponent(subject)}`;
    return <a href={href}>{siteConfig.supportEmail}</a>;
  }
  return <Link href="/support">our support page</Link>;
}
