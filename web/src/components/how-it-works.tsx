"use client";

import { useEffect, useRef, useState } from "react";
import { PhoneMock, type PhoneScreen } from "@/components/phone-mock";

const steps: { screen: PhoneScreen; kicker: string; title: string; body: string }[] = [
  {
    screen: "scan",
    kicker: "01 · Find",
    title: "Find what can get smaller.",
    body: "Not just what's big: the 4K videos, long recordings, Live Photos, and screenshots that can shrink without losing anything you'd notice.",
  },
  {
    screen: "review",
    kicker: "02 · Choose",
    title: "Shrink, trim, or let it go.",
    body: "Pick a method and a quality level and see exactly how much space you'll get back before anything changes. You confirm every step.",
  },
  {
    screen: "reclaim",
    kicker: "03 · Reclaim",
    title: "Same memories. Lighter phone.",
    body: "Your library keeps every moment, just smaller. Originals wait in Recently Deleted for 30 days, so you can compare and change your mind.",
  },
];

/** Apple-style pinned story: the phone stays put while the steps scroll past. */
export function HowItWorks() {
  const [active, setActive] = useState(0);
  const refs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) setActive(Number((entry.target as HTMLElement).dataset.index));
        }
      },
      { rootMargin: "-45% 0px -45% 0px" },
    );
    refs.current.forEach((el) => el && observer.observe(el));
    return () => observer.disconnect();
  }, []);

  return (
    <div className="grid gap-10 lg:grid-cols-2 lg:gap-20">
      <div className="hidden lg:block">
        <div className="sticky top-[max(4.5rem,calc(50vh-300px))] flex h-[600px] items-center justify-center">
          <div className="relative w-[280px]">
            {steps.map((step, i) => (
              <div
                key={step.screen}
                aria-hidden={i !== active}
                className={`transition-all duration-700 ease-[var(--ease-out-soft)] ${
                  i === 0 ? "relative" : "absolute inset-0"
                } ${i === active ? "opacity-100 [transform:none]" : "pointer-events-none opacity-0 [transform:translateY(16px)_scale(0.97)]"}`}
              >
                <PhoneMock screen={step.screen} />
              </div>
            ))}
            <ol className="absolute top-1/2 -left-14 flex -translate-y-1/2 flex-col gap-3" aria-hidden="true">
              {steps.map((step, i) => (
                <li
                  key={step.screen}
                  className={`size-2.5 rounded-full border-2 border-ink transition-colors duration-500 ${
                    i === active ? "bg-ink" : "bg-transparent"
                  }`}
                />
              ))}
            </ol>
          </div>
        </div>
      </div>

      <div>
        {steps.map((step, i) => (
          <div
            key={step.screen}
            ref={(el) => {
              refs.current[i] = el;
            }}
            data-index={i}
            className="flex flex-col justify-center py-10 lg:min-h-[78vh] lg:py-0"
          >
            <p className="eyebrow">{step.kicker}</p>
            <h3
              className={`mt-3 font-display text-[clamp(2rem,4vw,3.2rem)] leading-[1.02] font-extrabold transition-opacity duration-500 lg:max-w-md ${
                i === active ? "lg:opacity-100" : "lg:opacity-30"
              }`}
            >
              {step.title}
            </h3>
            <p className="mt-5 max-w-md text-lg leading-relaxed text-ink-soft">{step.body}</p>
            <div className="mt-10 flex justify-center lg:hidden">
              <PhoneMock screen={step.screen} className="max-w-[250px]" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
