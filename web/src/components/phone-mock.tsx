"use client";

import { useEffect, useRef, useState } from "react";
import { Illustration } from "@/components/ink";
import { between, clamp, SketchCard, SketchCheck, SketchProgress, SketchScene, SketchTap, SketchWrite } from "@/components/phone-sketch";

export type PhoneScreen = "scan" | "review" | "compress" | "reclaim";

/** Run visible, active demos only; hold the result before replaying the story. */
function useDemoProgress(active: boolean, paused: boolean) {
  const ref = useRef<HTMLDivElement>(null);
  const elapsed = useRef(0);
  // A finished screen also serves SSR, no-JS, and reduced motion.
  const [cel, setCel] = useState(-1);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let visible = false;
    let frame = 0;
    let previous = 0;

    function tick(now: number) {
      if (previous) elapsed.current += Math.min(now - previous, 100);
      previous = now;
      // Match iOS CelClock: 12 drawings/sec, with line boil held for two cels.
      // RAF only schedules the clock; React updates when a new drawing is due.
      setCel(Math.floor(elapsed.current * 12 / 1000));
      frame = requestAnimationFrame(tick);
    }

    function sync() {
      cancelAnimationFrame(frame);
      previous = 0;
      if (motion.matches) {
        frame = requestAnimationFrame(() => setCel(-1));
      } else if (visible && active && !paused && !document.hidden) {
        frame = requestAnimationFrame(tick);
      }
    }

    if (!active) elapsed.current = 0;
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (!visible) elapsed.current = 0;
      sync();
    }, { threshold: 0.25 });
    observer.observe(element);
    motion.addEventListener("change", sync);
    document.addEventListener("visibilitychange", sync);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      motion.removeEventListener("change", sync);
      document.removeEventListener("visibilitychange", sync);
    };
  }, [active, paused]);

  return { ref, progress: cel < 0 ? 1 : clamp((cel % 108) / 78), frame: Math.max(cel, 0) };
}

// Illustrative sample library, matching the app's Demo Mode.
export function PhoneMock({ screen, className, active = true, paused = false }: {
  screen: PhoneScreen;
  className?: string;
  active?: boolean;
  paused?: boolean;
}) {
  const { ref, progress, frame } = useDemoProgress(active, paused);
  return (
    <div
      ref={ref}
      data-phone-demo={screen}
      className={`relative aspect-[9/19] w-full max-w-[300px] rounded-[48px] border-[3px] border-ink bg-ink p-[9px] shadow-[10px_12px_0_var(--mint)] ${className ?? ""}`}
      role="img"
      aria-label={labels[screen]}
    >
      <div className="relative h-full overflow-hidden rounded-[39px] bg-paper">
        <div className="absolute top-2.5 left-1/2 z-10 h-[22px] w-[84px] -translate-x-1/2 rounded-full bg-ink" />
        <div className="flex items-center justify-between px-7 pt-3 text-[10px] font-semibold" aria-hidden="true">
          <span>9:41</span><span className="tracking-tight">●●● ▮</span>
        </div>
        <div className="phone-demo-content px-4 pt-6" aria-hidden="true">
          <SketchScene progress={progress} frame={frame}>
            {screen === "scan" && <ScanScreen progress={progress} />}
            {screen === "review" && <ChooseScreen progress={progress} />}
            {screen === "compress" && <CompressScreen progress={progress} />}
            {screen === "reclaim" && <ReclaimScreen progress={progress} />}
          </SketchScene>
        </div>
        <div className="absolute inset-x-0 bottom-3 text-center" aria-hidden="true">
          <p className="text-[9px] text-ink-faint">Demo · sample library</p>
          <div className="mx-auto mt-2 h-1 w-20 rounded-full bg-ink/70" />
        </div>
      </div>
    </div>
  );
}

const labels: Record<PhoneScreen, string> = {
  scan: "Animated demo: a library scan finds videos, Live Photos, and screenshots that could save up to 43 GB.",
  review: "Animated demo: selecting Balanced video compression previews a change from 4.2 GB to 1.9 GB, saving 2.3 GB before confirmation.",
  compress: "Animated demo: after confirmation, Concert.MOV compresses from 4.2 GB to 1.9 GB entirely on the iPhone.",
  reclaim: "Animated demo: the savings count up to 2.3 GB, with the video kept and its original recoverable in Recently Deleted for 30 days.",
};

function ProgressBar({ value }: { value: number }) {
  return <SketchProgress value={value} />;
}

function DemoTap({ progress, at }: { progress: number; at: number }) {
  return <SketchTap progress={progress} at={at} />;
}

function ScanScreen({ progress }: { progress: number }) {
  const scan = between(progress, 0.04, 0.73);
  const rows = [
    { name: "4K videos", detail: "46 items · 41.2 GB", save: "−29 GB", ill: "ill-video" },
    { name: "Long recordings", detail: "12 items · 9.8 GB", save: "−7 GB", ill: "ill-reset" },
    { name: "Live Photos", detail: "1,840 items · 5.6 GB", save: "−2.7 GB", ill: "ill-photo" },
    { name: "Screenshots", detail: "2,140 items · 6.8 GB", save: "−4.4 GB", ill: "ill-screenshot" },
  ];
  return (
    <div>
      <p className="phone-demo-eyebrow">01 / Find</p>
      <p className="font-display text-[22px] font-extrabold"><SketchWrite>Worth shrinking</SketchWrite></p>
      <SketchCard start={0.04} height={66} tone="mint-soft" className="mt-3 p-3">
        <div className="flex justify-between text-[10px] font-semibold"><span className="font-hand text-[13px]">{scan < 1 ? "Looking through your library…" : "Scan complete"}</span><span className="tabular-nums">{Math.round(scan * 100)}%</span></div>
        <div className="mt-2"><ProgressBar value={scan} /></div>
      </SketchCard>
      <ul className="relative mt-3 space-y-2">
        {rows.map((row, i) => {
          return (
            <li key={row.name}>
              <SketchCard start={0.12 + i * 0.11} seed={5 + i * 31} className="p-2.5">
                <div className="flex items-center gap-2">
                  <Illustration name={row.ill} size={30} />
                  <div className="min-w-0 flex-1"><p className="text-[11px] leading-tight font-semibold">{row.name}</p><p className="text-[9px] text-ink-faint">{row.detail}</p></div>
                  <span className="font-hand text-[13px] font-bold text-mint-deep">{row.save}</span>
                </div>
              </SketchCard>
            </li>
          );
        })}
      </ul>
      <p className="mt-3 text-center text-[11px] text-ink-soft"><SketchWrite start={0.7} length={0.15}>Up to <strong className="tabular-nums text-ink">{Math.round(scan * 43)} GB</strong> worth shrinking</SketchWrite></p>
      <SketchCard start={0.8} length={0.2} height={38} radius={18} tone="ink" className="relative mt-3 py-2.5 text-center text-[11px] font-semibold text-paper">
        Start with 4K videos <span className="ml-1">→</span><DemoTap progress={progress} at={0.82} />
      </SketchCard>
    </div>
  );
}

/** Code-drawn thumbnail keeps the same video recognizable throughout the story. */
function VideoPreview({ compact = false }: { compact?: boolean }) {
  return (
    <SketchCard start={0.08} height={compact ? 94 : 108} radius={10} seed={29} tone="mint-soft" className={`relative ${compact ? "h-[94px]" : "h-[108px]"}`}>
      <svg className="block h-full w-full" viewBox="0 0 224 94" aria-hidden="true">
        <path d="M 35 9 L 58 66 L 16 66 Z M 169 9 L 207 65 L 157 65 Z" fill="var(--mint)" opacity="0.65" />
        <path d="M 35 9 Q 46 34 58 66 M 35 9 Q 23 40 16 66 M 169 9 L 207 65 M 169 9 L 157 65 M 13 68 Q 110 65 211 68" fill="none" stroke="var(--ink)" strokeWidth="1.2" strokeLinecap="round" />
        <path d="M 23 60 l 8 -17 M 28 64 l 9 -19 M 178 35 l 9 17 M 181 30 l 12 25" fill="none" stroke="var(--ink)" strokeWidth="1" opacity="0.3" />
        {Array.from({ length: 8 }, (_, i) => <path key={i} d={`M ${20 + i * 26} 77 q -7 -19 1 -19 q 10 0 7 20`} fill="var(--paper)" stroke="var(--ink)" strokeWidth="1.3" />)}
        <path d="M 96 33 Q 99 22 111 25 Q 129 24 128 40 Q 127 56 111 56 Q 96 56 96 33 Z" fill="var(--surface)" stroke="var(--ink)" strokeWidth="1.6" />
        <path d="M 108 32 L 119 40 L 108 47 Z" fill="var(--ink)" />
      </svg>
      <span className="absolute bottom-1.5 left-2 font-hand text-[11px] font-semibold">Concert.MOV</span>
      <span className="absolute right-2 bottom-2 text-[8px] font-semibold">11:04</span>
    </SketchCard>
  );
}

function ChooseScreen({ progress }: { progress: number }) {
  const selected = progress < 0.12 ? -1 : progress < 0.4 ? 0 : 1;
  const levels = [
    { name: "Light", size: "2.9 GB", save: "1.3 GB" },
    { name: "Balanced", size: "1.9 GB", save: "2.3 GB" },
    { name: "Maximum", size: "1.2 GB", save: "3.0 GB" },
  ];
  return (
    <div>
      <p className="phone-demo-eyebrow">02 / Choose</p>
      <p className="font-display text-[22px] font-extrabold"><SketchWrite>Make it smaller.</SketchWrite></p>
      <p className="mt-1 text-[10px] text-ink-soft"><SketchWrite start={0.1}>4K · 60 fps · 11 min · 4.2 GB</SketchWrite></p>
      <div className="mt-3"><VideoPreview compact /></div>
      <SketchCard start={0.23} height={30} radius={14} className="mt-3 p-1 text-[10px] font-semibold"><div className="flex gap-1"><span className="flex-1 rounded-full bg-ink py-1 text-center text-paper">Compress</span><span className="flex-1 py-1 text-center text-ink-soft">Trim</span></div></SketchCard>
      <ul className="mt-2 space-y-1.5">
        {levels.map((level, i) => (
          <li key={level.name}>
            <SketchCard start={0.31 + i * 0.1} height={34} radius={9} seed={40 + i} tone={i === selected ? "mint-soft" : "surface"} className={`px-2.5 py-2 text-[11px] ${i === selected ? "font-semibold" : ""}`}>
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-2"><span className="grid size-3.5 place-items-center rounded-[45%] border border-ink/40">{i === selected && <SketchCheck amount={between(progress, i === 0 ? 0.12 : 0.4, i === 0 ? 0.17 : 0.45)} className="size-3.5 text-mint-deep" />}</span>{level.name}</span>
                <span className="tabular-nums">{level.size}</span>
              </div>
              {i < 2 && <DemoTap progress={progress} at={i === 0 ? 0.1 : 0.38} />}
            </SketchCard>
          </li>
        ))}
      </ul>
      <SketchCard start={0.75} length={0.22} height={38} radius={18} tone="ink" className="relative mt-3 py-2.5 text-center text-[12px] font-semibold text-paper">
        {selected < 0 ? "Choose a quality level" : `Save ${levels[selected].save}`}<DemoTap progress={progress} at={0.77} />
      </SketchCard>
      <p className="mt-2 text-center text-[9px] text-ink-faint"><SketchWrite start={0.85} length={0.15}>Nothing changes until you confirm.</SketchWrite></p>
    </div>
  );
}

function CompressScreen({ progress }: { progress: number }) {
  const compression = between(progress, 0.18, 0.82);
  const done = compression === 1;
  return (
    <div>
      <p className="phone-demo-eyebrow">03 / Shrink</p>
      <p className="font-display text-[22px] font-extrabold"><SketchWrite>{done ? "Ready to keep." : "A little lighter…"}</SketchWrite></p>
      <p className="mt-1 text-[10px] text-ink-soft"><SketchWrite start={0.1}>Balanced quality · on your iPhone</SketchWrite></p>
      <div className="mt-4"><VideoPreview /></div>
      <SketchCard start={0.3} height={168} seed={67} className="mt-4 p-3">
        <div className="flex items-center justify-between text-[11px] font-semibold"><span>{done ? "Compression complete ✓" : "Compressing video…"}</span><span className="tabular-nums text-mint-deep">{Math.round(compression * 100)}%</span></div>
        <div className="mt-3"><ProgressBar value={compression} /></div>
        <div className="mt-4 flex items-baseline justify-between text-[10px] text-ink-soft"><span>Original</span><span className="tabular-nums">4.2 GB</span></div>
        <SketchProgress value={1} className="mt-1.5" />
        <div className="mt-3 flex items-baseline justify-between text-[10px] font-semibold"><span>Smaller copy</span><span className="tabular-nums text-mint-deep">{(4.2 - compression * 2.3).toFixed(1)} GB</span></div>
        <SketchProgress value={1 - compression * (2.3 / 4.2)} className="mt-1.5" />
      </SketchCard>
      <SketchCard start={0.53} height={46} seed={91} tone="mint-soft" className="mt-3 p-2.5 text-[10px] font-medium text-mint-deep"><div className="flex items-center gap-2"><Illustration name="ill-lock" size={24} /><span>Your video never leaves your phone.</span></div></SketchCard>
      <p className="mt-3 text-center font-hand text-[15px] font-semibold" style={{ visibility: done ? "visible" : "hidden" }}>Same moment. 55% smaller.</p>
    </div>
  );
}

function ReclaimScreen({ progress }: { progress: number }) {
  const reclaimed = between(progress, 0.08, 0.32);
  const stamp = between(progress, 0.04, 0.1);
  const stampScale = stamp === 0 ? 0 : stamp < 0.5 ? 1.15 : stamp < 1 ? 0.96 : 1;
  return (
    <div className="text-center">
      <p className="phone-demo-eyebrow text-left">04 / Reclaim</p>
      <div className="relative mx-auto mt-3 w-fit" style={{ transform: `scale(${stampScale}) rotate(${stamp < 1 ? -4 : 0}deg)` }}>
        <Illustration name="ill-piggy" size={88} />
        <span className="absolute -right-1 bottom-0 grid size-7 place-items-center rounded-[43%] border border-ink bg-mint text-sm font-bold text-[#1a1a17]"><SketchCheck amount={between(progress, 0.3, 0.36)} className="size-5" /></span>
      </div>
      <p className="mt-3 font-display text-[40px] leading-none font-extrabold tabular-nums"><SketchWrite start={0.12}>{(reclaimed * 2.3).toFixed(1)} GB</SketchWrite></p>
      <p className="mt-1 text-[12px] font-semibold text-mint-deep"><SketchWrite start={0.4}>lighter · memory kept</SketchWrite></p>
      <SketchCard start={0.65} length={0.31} height={97} radius={6} seed={112} className="mt-5 p-3 text-left">
        <p className="font-hand text-[14px] font-semibold">Your space receipt</p>
        <div className="mt-2 flex justify-between border-b border-dashed border-ink/15 pb-2 text-[10px] text-ink-soft"><span>Concert.MOV</span><span>4.2 → 1.9 GB</span></div>
        <div className="mt-2 flex justify-between text-[11px] font-bold"><span>Space saved</span><span className="text-mint-deep">2.3 GB</span></div>
      </SketchCard>
      <SketchCard start={0.78} length={0.22} height={78} seed={145} tone="mint-soft" className="mt-3 p-3 text-left"><div className="flex gap-2">
        <Illustration name="ill-shield-check" size={28} />
        <div><p className="text-[10px] font-semibold">Original kept for 30 days</p><p className="mt-1 text-[9px] leading-snug text-ink-soft">Compare or undo in Recently Deleted. Empty it when you&apos;re ready to reclaim the space.</p></div>
      </div></SketchCard>
    </div>
  );
}
