"use client";

import { createContext, useContext, useId, type CSSProperties, type ReactNode } from "react";
import "./phone-sketch.css";

// Web counterparts of iOS DrawIn, InkIn, BoilClock, and SketchProgressBar.
// A 12fps cel clock holds each of three line-boil drawings for two frames.
const SketchContext = createContext({ progress: 1, frame: 0, pose: 0 });
export const clamp = (value: number) => Math.min(1, Math.max(0, value));
export const between = (value: number, start: number, end: number) => clamp((value - start) / (end - start));
const penEase = (t: number) => t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2;

export function SketchScene({ progress, frame, children }: { progress: number; frame: number; children: ReactNode }) {
  return (
    <SketchContext.Provider value={{ progress: clamp(progress / 0.48), frame, pose: Math.floor(frame / 2) % 3 }}>
      <div className="phone-sketch-scene">{children}</div>
    </SketchContext.Provider>
  );
}

// Same spatial field as Sketch.boil: neighboring points shift together.
function point(x: number, y: number, pose: number, amount = 0.65) {
  const phase = pose * 2.399963;
  return [
    x + amount * Math.sin(y * 0.11 + phase) * Math.cos(x * 0.05 - phase * 0.7),
    y + amount * Math.cos(x * 0.09 + phase * 1.3) * Math.sin(y * 0.06 + phase),
  ].map(value => Math.round(value * 100) / 100);
}

/** One continuous, gently uneven pen stroke, including the rounded corners. */
function box(width: number, height: number, radius: number, seed: number, pose: number) {
  const r = Math.min(radius, height / 2 - 2);
  const points: number[][] = [];
  const corners = [[r + 2, r + 2, 180], [width - r - 2, r + 2, 270], [width - r - 2, height - r - 2, 0], [r + 2, height - r - 2, 90]];
  for (const [index, [cx, cy, start]] of corners.entries()) {
    for (let i = 0; i <= 4; i++) {
      const angle = (start + i * 22.5) * Math.PI / 180;
      const x = cx + Math.cos(angle) * r;
      const y = cy + Math.sin(angle) * r;
      points.push(point(x, y, pose, 0.5 + Math.sin(seed + i) * 0.15));
    }
    // Break the long edges into pen-length segments so they can gently bow.
    const next = corners[(index + 1) % 4];
    const endAngle = (next[2]) * Math.PI / 180;
    const end = [next[0] + Math.cos(endAngle) * r, next[1] + Math.sin(endAngle) * r];
    const from = points[points.length - 1];
    const count = Math.floor(Math.hypot(end[0] - from[0], end[1] - from[1]) / 28);
    for (let j = 1; j < count; j++) {
      points.push(point(from[0] + (end[0] - from[0]) * j / count, from[1] + (end[1] - from[1]) * j / count, pose));
    }
  }
  const [first, ...rest] = points;
  return `M ${first.join(" ")} ${rest.map((p, i) => {
    const next = points[(i + 2) % points.length];
    return `Q ${p.join(" ")} ${(p[0] + next[0]) / 2} ${(p[1] + next[1]) / 2}`;
  }).join(" ")} Q ${first.join(" ")} ${first.join(" ")} Z`;
}

/** Trace the card in ink first; a flat ink wash follows across its contents. */
export function SketchCard({ children, start = 0.12, length = 0.31, height = 54, radius = 13, seed = 5, tone = "surface", className = "", style }: {
  children: ReactNode;
  start?: number;
  length?: number;
  height?: number;
  radius?: number;
  seed?: number;
  tone?: "surface" | "mint-soft" | "ink";
  className?: string;
  style?: CSSProperties;
}) {
  const { progress, pose } = useContext(SketchContext);
  const local = between(progress, start, start + length);
  const trace = penEase(between(local, 0, 0.7));
  const wash = penEase(between(local, 0.45, 1));
  const path = box(224, height, radius, seed, pose);
  const id = useId();
  return (
    <div className={`phone-sketch-card ${className}`} style={style}>
      <svg className="phone-sketch-outline" viewBox={`0 0 224 ${height}`} preserveAspectRatio="none" aria-hidden="true">
        <defs><clipPath id={id}><rect width={224 * wash} height={height} /></clipPath></defs>
        <g clipPath={`url(#${id})`}>
          <path d={path} fill="var(--ink)" opacity="0.12" transform="translate(-1 2)" />
          <path d={path} fill={`var(--${tone})`} />
        </g>
        <path d={path} fill="none" stroke="var(--ink)" strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - trace} opacity={local > 0 ? 0.8 : 0} />
      </svg>
      <div className="relative" style={{ visibility: wash === 0 ? "hidden" : "visible", clipPath: `inset(-4px ${100 - wash * 100}% -4px -4px)` }}>{children}</div>
    </div>
  );
}

/** The iOS title's left-to-right handwriting reveal, held on each cel. */
export function SketchWrite({ children, className = "", start = 0, length = 0.16 }: {
  children: ReactNode;
  className?: string;
  start?: number;
  length?: number;
}) {
  const { progress, pose } = useContext(SketchContext);
  const written = between(progress, start, start + length);
  return <span className={`phone-sketch-write ${className}`} style={{ visibility: written === 0 ? "hidden" : "visible", clipPath: `inset(-2px ${100 - written * 100}% -2px -2px)`, transform: `translate(${[0, 0.12, -0.12][pose]}px, ${[0.1, -0.1, 0][pose]}px)` }}>{children}</span>;
}

/** Wobbly sticker track, offset shadow, and marching pencil hatching from iOS. */
export function SketchProgress({ value, className = "" }: { value: number; className?: string }) {
  const { frame, pose } = useContext(SketchContext);
  const id = useId();
  const path = box(224, 17, 5, 5, pose);
  const width = 224 * clamp(value);
  return (
    <svg className={`phone-sketch-progress ${className}`} viewBox="0 0 226 22" preserveAspectRatio="none" aria-hidden="true">
      <defs><clipPath id={id}><path d={path} /></clipPath><clipPath id={`${id}-fill`}><rect width={width} height="20" /></clipPath></defs>
      <path d={path} fill="var(--ink)" transform="translate(-1 3)" />
      <path d={path} fill="var(--surface)" />
      <g clipPath={`url(#${id})`}>
        <g clipPath={`url(#${id}-fill)`}>
          <rect width="224" height="20" fill="var(--mint)" />
          {Array.from({ length: 28 }, (_, i) => <path key={i} d={`M ${i * 9 - 16 + frame % 9} 19 l 14 -20`} stroke="var(--ink)" strokeWidth="1.2" opacity="0.26" />)}
        </g>
      </g>
      <path d={path} fill="none" stroke="var(--ink)" strokeWidth="1.6" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

export function SketchCheck({ amount = 1, className = "" }: { amount?: number; className?: string }) {
  const { pose } = useContext(SketchContext);
  return <svg className={className} viewBox="0 0 20 20" aria-hidden="true"><path d={`M ${point(3, 10, pose).join(" ")} Q 7 12 8 15 Q 12 9 17 5`} fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - amount} /></svg>;
}

/** A pen-drawn tap annotation, held and then lifted, rather than a soft halo. */
export function SketchTap({ progress, at }: { progress: number; at: number }) {
  const { pose } = useContext(SketchContext);
  const local = between(progress, at, at + 0.1);
  const show = local > 0 && local < 1;
  return (
    <svg className="phone-sketch-tap" viewBox="0 0 46 40" aria-hidden="true" style={{ visibility: show ? "visible" : "hidden", transform: `rotate(${[0, -3, 2][pose]}deg)` }}>
      <path d="M 14 20 Q 8 9 16 7 Q 22 6 25 18 M 20 18 Q 29 11 30 20 L 29 30 Q 25 36 18 31 L 9 25 Q 7 20 12 21 L 17 24" fill="var(--paper)" stroke="var(--ink)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M 9 6 L 6 2 M 23 4 L 25 0 M 31 10 L 36 7" fill="none" stroke="var(--mint-deep)" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}
