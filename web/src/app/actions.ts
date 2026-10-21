"use server";

// Waitlist signup. Forwards { email, source, joinedAt } as JSON to
// WAITLIST_WEBHOOK_URL (server-only), so any email tool, n8n, or Zapier hook
// can receive it. `source` is the page the visitor signed up from, which is
// how we learn which guides convert.

export type WaitlistState = {
  status: "idle" | "success" | "error";
  message: string;
};

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export async function joinWaitlist(
  _prev: WaitlistState,
  formData: FormData,
): Promise<WaitlistState> {
  // Honeypot: real visitors never see or fill this field.
  if (formData.get("company")) {
    return { status: "success", message: "You're on the list." };
  }

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const source = String(formData.get("source") ?? "unknown").slice(0, 120);

  if (!EMAIL.test(email) || email.length > 254) {
    return { status: "error", message: "That email doesn't look right. Mind checking it?" };
  }

  const webhook = process.env.WAITLIST_WEBHOOK_URL;
  if (!webhook) {
    if (process.env.NODE_ENV !== "production") {
      console.info(`[waitlist] ${email} from ${source} (WAITLIST_WEBHOOK_URL not set)`);
      return { status: "success", message: "You're on the list. We'll email you at launch." };
    }
    console.error("[waitlist] WAITLIST_WEBHOOK_URL is not configured");
    return { status: "error", message: "Signups are briefly unavailable. Please try again soon." };
  }

  try {
    const res = await fetch(webhook, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, source, joinedAt: new Date().toISOString() }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`webhook responded ${res.status}`);
  } catch (error) {
    console.error("[waitlist] forwarding failed", error);
    return { status: "error", message: "Something went wrong on our end. Please try again." };
  }

  return { status: "success", message: "You're on the list. We'll email you at launch." };
}
