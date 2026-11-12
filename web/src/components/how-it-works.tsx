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
    screen: "compress",
    kicker: "03 · Shrink",
    title: "Watch the size come down.",
    body: "Make a smaller copy right on your iPhone. Follow the progress as a 4.2 GB video becomes 1.9 GB, with the quality level you chose.",
  },
  {
    screen: "reclaim",
    kicker: "04 · Reclaim",
    title: "Same memories. Lighter phone.",
    body: "Your library keeps every moment, just smaller. See your savings, compare with the original, and empty Recently Deleted when you're ready to reclaim the space. You have 30 days to change your mind.",
  },
];

/** Pinned story: the phone redraws in ink while the steps scroll past. */
export function HowItWorks() {
  const [active, setActive] = useState(0);
  const [paused, setPaused] = useState(false);
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
                className={`${
                  i === 0 ? "relative" : "absolute inset-0"
                } ${i === active ? "opacity-100" : "pointer-events-none opacity-0"}`}
              >
                <PhoneMock screen={step.screen} active={i === active} paused={paused} />
              </div>
            ))}
            <ol className="absolute top-1/2 -left-16 flex -translate-y-1/2 flex-col" aria-label="Demo steps">
              {steps.map((step, i) => (
                <li key={step.screen}>
                  <button
                    type="button"
                    aria-label={`Show step ${i + 1}: ${step.kicker.split(" · ")[1]}`}
                    aria-current={i === active ? "step" : undefined}
                    onClick={() => refs.current[i]?.scrollIntoView({ block: "center" })}
                    className="grid size-8 place-items-center rounded-full"
                  >
                    <span className={`size-2.5 rounded-full border-2 border-ink transition-colors duration-500 ${i === active ? "bg-ink" : "bg-transparent"}`} />
                  </button>
                </li>
              ))}
            </ol>
            <div className="absolute -bottom-12 inset-x-0 flex justify-center">
              <DemoControls paused={paused} onToggle={() => setPaused((value) => !value)} />
            </div>
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
            <div className="mt-10 flex flex-col items-center gap-6 lg:hidden">
              <PhoneMock screen={step.screen} paused={paused} className="!max-w-[280px]" />
              <DemoControls paused={paused} onToggle={() => setPaused((value) => !value)} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function DemoControls({ paused, onToggle }: { paused: boolean; onToggle: () => void }) {
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-pressed={paused}
      className="flex min-h-10 items-center gap-2 rounded-full border border-ink/20 bg-surface px-4 text-xs font-semibold text-ink-soft transition-colors hover:border-ink hover:text-ink motion-reduce:hidden"
    >
      <span aria-hidden="true">{paused ? "▶" : "Ⅱ"}</span>
      {paused ? "Play demos" : "Pause demos"}
    </button>
  );
}
