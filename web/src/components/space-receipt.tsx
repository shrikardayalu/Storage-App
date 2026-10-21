"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";
import { Illustration } from "@/components/ink";

// The hero's self-playing demo: a receipt where each line item shrinks in turn
// and the total climbs, while "deleted" stays at zero. Sample numbers only.

type Line = { name: string; detail: string; method: string; from: number; to: number; ill: string };

const lines: Line[] = [
  { name: "Concert.MOV", detail: "4K · 60 fps · 11 min", method: "Re-encoded to 1080p", from: 4.2, to: 1.1, ill: "ill-video" },
  { name: "Screen recording", detail: "9 min", method: "Trimmed to the 40 s you need", from: 2.7, to: 0.2, ill: "ill-reset" },
  { name: "1,840 Live Photos", detail: "photo + 3 s of video each", method: "Kept as stills", from: 5.6, to: 2.9, ill: "ill-photo" },
  { name: "2,140 screenshots", detail: "saved as PNG", method: "Re-saved, same pixels", from: 6.8, to: 2.4, ill: "ill-screenshot" },
];

const totalSaved = lines.reduce((sum, l) => sum + (l.from - l.to), 0);
const STEP_MS = 1500;
const HOLD_MS = 3800;

function formatGb(gb: number) {
  return gb < 1 ? `${Math.round(gb * 1000)} MB` : `${gb.toFixed(1)} GB`;
}

/** Tweens a number toward `value` whenever it changes. */
function useTween(value: number, duration = 900) {
  const [shown, setShown] = useState(value);
  const from = useRef(value);

  useEffect(() => {
    const start = performance.now();
    const origin = from.current;
    let frame = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      const next = origin + (value - origin) * eased;
      from.current = next;
      setShown(next);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value, duration]);

  return shown;
}

export function SpaceReceipt() {
  // Rows completed so far. Reduced-motion visitors get the finished receipt.
  const [done, setDone] = useState(0);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let timer = 0;
    let visible = true;
    let step = 0;

    const run = () => {
      window.clearTimeout(timer);
      if (!visible || document.hidden) return;
      if (reduced) return setDone(lines.length);
      setDone(step);
      if (step < lines.length) {
        step += 1;
        timer = window.setTimeout(run, step === 1 ? 900 : STEP_MS);
      } else {
        step = 0;
        timer = window.setTimeout(run, HOLD_MS);
      }
    };

    const io = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) run();
      else window.clearTimeout(timer);
    });
    if (ref.current) io.observe(ref.current);
    const onVisibility = () => !document.hidden && visible && run();
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      window.clearTimeout(timer);
      io.disconnect();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  const saved = lines.slice(0, done).reduce((sum, l) => sum + (l.from - l.to), 0);
  const savedShown = useTween(saved);

  return (
    <div ref={ref} className="relative">
      <div className="relative mx-auto w-full max-w-[400px]">
      <div aria-hidden="true" className="absolute inset-x-0 top-0 bottom-6 translate-x-3 translate-y-3 rotate-[1.2deg] rounded-[20px] border-2 border-ink bg-mint" />
      <div className="relative [filter:drop-shadow(0_14px_18px_rgb(26_26_23/0.16))]">
      <div
        role="img"
        aria-label={`Example receipt: ${formatGb(totalSaved)} freed by shrinking videos, Live Photos, and screenshots, with nothing deleted`}
        className="receipt relative bg-surface px-6 pt-7 pb-12 sm:px-8"
      >
        <div aria-hidden="true">
          <div className="flex items-baseline justify-between">
            <p className="font-display text-xl font-extrabold">Space receipt</p>
            <p className="font-hand text-lg text-ink-faint">no. 0001</p>
          </div>
          <p className="mt-1 text-xs tracking-[0.2em] text-ink-faint uppercase">Your iPhone · today</p>
          <hr className="mt-4 border-t-2 border-dashed border-ink/25" />

          <ul className="mt-2">
            {lines.map((line, i) => (
              <ReceiptLine key={line.name} line={line} done={i < done} active={i === done} />
            ))}
          </ul>

          <hr className="mt-2 border-t-2 border-dashed border-ink/25" />
          <div className="mt-4 flex items-end justify-between">
            <div>
              <p className="text-xs font-semibold tracking-[0.18em] text-ink-faint uppercase">Space freed</p>
              <p className="font-display text-5xl leading-none font-extrabold tabular-nums">{formatGb(savedShown)}</p>
            </div>
            <div className="text-right">
              <p className="text-xs font-semibold tracking-[0.18em] text-ink-faint uppercase">Deleted</p>
              <p className="font-display text-5xl leading-none font-extrabold text-mint-deep tabular-nums">0</p>
            </div>
          </div>
        </div>
      </div>
      </div>
      </div>

      {/* Rubber stamp lands once the receipt is complete. */}
      <div
        aria-hidden="true"
        className={`absolute -right-2 -bottom-7 rotate-[-10deg] bg-surface/85 rounded-xl border-[3px] border-tomato px-3 py-1.5 text-center font-display font-extrabold tracking-wide text-tomato uppercase transition-all duration-300 ease-[var(--ease-spring)] sm:-right-8 ${
          done === lines.length ? "scale-100 opacity-90" : "scale-150 opacity-0"
        }`}
      >
        <span className="block text-[11px] leading-tight">memories kept</span>
        <span className="block text-2xl leading-none">100%</span>
      </div>
    </div>
  );
}

function ReceiptLine({ line, done, active }: { line: Line; done: boolean; active: boolean }) {
  const size = useTween(done ? line.to : line.from, 1000);
  const ratio = line.to / line.from;

  return (
    <li
      className={`relative -mx-3 rounded-xl px-3 py-3 transition-colors duration-500 ${active ? "bg-mint-soft/60" : ""}`}
    >
      <div className="flex items-start gap-3">
        <Illustration name={line.ill} size={38} priority className="mt-0.5 shrink-0" />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline justify-between gap-3">
            <p className="truncate text-[0.95rem] font-semibold">{line.name}</p>
            <p className="shrink-0 text-[0.95rem] font-bold tabular-nums">
              <span
                className={`mr-1.5 text-xs font-medium text-ink-faint line-through transition-opacity duration-500 ${
                  done ? "opacity-100" : "opacity-0"
                }`}
              >
                {formatGb(line.from)}
              </span>
              <span className={done ? "text-mint-deep" : ""}>{formatGb(size)}</span>
            </p>
          </div>
          <p className="mt-0.5 truncate text-xs text-ink-faint">
            {done ? <span className="font-hand text-sm text-ink-soft">✓ {line.method}</span> : line.detail}
          </p>
          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-paper-deep">
            <div
              className={`h-full origin-left rounded-full transition-[transform,background-color] duration-1000 ease-[var(--ease-out-soft)] ${
                done ? "bg-mint" : "bg-ink"
              }`}
              style={{ transform: `scaleX(${done ? ratio : 1})` } as CSSProperties}
            />
          </div>
        </div>
      </div>
    </li>
  );
}
