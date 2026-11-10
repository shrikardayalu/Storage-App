"use client";

import { useActionState, useId } from "react";
import { joinWaitlist, type WaitlistState } from "@/app/actions";

const initialState: WaitlistState = { status: "idle", message: "" };

/**
 * Email capture. `source` records where the signup happened (page + spot on
 * the page) so the content loop can see which guides actually convert.
 */
export function WaitlistForm({
  source,
  tone = "light",
  buttonLabel = "Join the waitlist",
}: {
  source: string;
  tone?: "light" | "dark";
  buttonLabel?: string;
}) {
  const [state, formAction, pending] = useActionState(joinWaitlist, initialState);
  const id = useId();
  const dark = tone === "dark";

  if (state.status === "success") {
    return (
      <p
        role="status"
        className={`flex items-center gap-3 rounded-full py-3 pr-5 pl-3 font-semibold ${
          dark ? "bg-on-band text-band" : "bg-ink text-paper"
        }`}
      >
        <span aria-hidden="true" className="grid size-8 place-items-center rounded-full bg-mint text-ink">
          ✓
        </span>
        {state.message}
      </p>
    );
  }

  return (
    <form action={formAction} className="w-full max-w-md">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <label htmlFor={`${id}-email`} className="sr-only">
          Email address
        </label>
        <input
          id={`${id}-email`}
          name="email"
          type="email"
          required
          autoComplete="email"
          inputMode="email"
          placeholder="you@email.com"
          aria-describedby={`${id}-msg`}
          className={`min-w-0 flex-1 rounded-full px-5 py-3 text-base focus:outline-none ${
            dark
              ? "bg-on-band/15 text-on-band placeholder:text-on-band/50"
              : "bg-paper-deep text-ink placeholder:text-ink-faint"
          }`}
        />
        <input type="hidden" name="source" value={source} />
        {/* Honeypot for bots; hidden from people and assistive tech. */}
        <input
          type="text"
          name="company"
          tabIndex={-1}
          autoComplete="off"
          aria-hidden="true"
          className="absolute -left-[9999px] h-0 w-0 opacity-0"
        />
        <button
          type="submit"
          disabled={pending}
          className={`btn-ink shrink-0 px-5 py-3 text-sm whitespace-nowrap disabled:opacity-60 ${
            dark ? "bg-on-band text-band" : ""
          }`}
        >
          {pending ? "Joining…" : buttonLabel}
        </button>
      </div>
      <p
        id={`${id}-msg`}
        aria-live="polite"
        className={`mt-2.5 pl-4 text-sm ${
          state.status === "error" ? "font-medium text-tomato" : dark ? "text-on-band/70" : "text-ink-faint"
        }`}
      >
        {state.status === "error" ? state.message : "One email when we launch. Free to start. No spam."}
      </p>
    </form>
  );
}
