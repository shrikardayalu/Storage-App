"use client";

import { usePathname } from "next/navigation";
import { useLayoutEffect } from "react";

/** One-shot ink entrances. Animation state stays outside React's markup. */
export function RevealObserver() {
  const pathname = usePathname();

  useLayoutEffect(() => {
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const seen = new WeakSet<Element>();
    const entrances = new Map<Element, Animation[]>();
    const animations: Animation[] = [];
    const targets = [...document.querySelectorAll(
      "[data-reveal], .draw, main h2, main h3, main .eyebrow, main .ill-light, main .ill-dark",
    )].filter((el) => !el.closest(".phone-sketch-scene") &&
      (!el.closest(".home-hero") || el.matches("[data-reveal], .draw")));

    const play = (el: Element, frames: Keyframe[], duration: number, delay = 0, extra: KeyframeAnimationOptions = {}) => {
      const animation = el.animate(frames, { duration, delay, fill: "both", ...extra });
      animation.pause();
      animations.push(animation);
    };
    const wash = (el: Element, delay = 0) => play(el, [
      { clipPath: "inset(-12px 105% -16px -12px)" },
      { clipPath: "inset(-12px -16px -16px -12px)" },
    ], 650, delay, { easing: "steps(10)" });

    const prepare = (el: Element) => {
      const delay = Number(getComputedStyle(el).getPropertyValue("--reveal-delay")) || 0;
      if (el.matches("[data-reveal]")) {
        play(el, [{ opacity: 0, transform: "translateY(12px)" }, { opacity: 1, transform: "none" }],
          650, delay, { easing: "cubic-bezier(0.16, 1, 0.3, 1)" });
        if (el.matches(".sticker")) {
          const style = getComputedStyle(el);
          play(el, [
            { backgroundColor: "transparent", boxShadow: "none", offset: 0 },
            { backgroundColor: "transparent", boxShadow: "none", offset: 0.65 },
            { backgroundColor: style.backgroundColor, boxShadow: style.boxShadow },
          ], 700, delay, { easing: "steps(1)", fill: "backwards" });
          play(el, [{ "--sketch-turn": "0deg" }, { "--sketch-turn": "360deg" }],
            750, delay, { easing: "steps(12)", pseudoElement: "::after" });
          [...el.children].forEach((child) => wash(child, delay + 320));
        }
      } else if (el.matches(".draw")) {
        el.querySelectorAll("path").forEach((path) => {
          const length = getComputedStyle(el).getPropertyValue("--len").trim() || "600";
          play(path, [{ strokeDashoffset: length }, { strokeDashoffset: "0" }], 1100, 200,
            { easing: "cubic-bezier(0.16, 1, 0.3, 1)" });
        });
      } else if (!el.closest(".sticker[data-reveal]")) {
        wash(el);
      }
    };
    // Apply each entrance's first frame before paint, even below the viewport.
    // Waiting until intersection exposes the text before the ink wash starts.
    targets.forEach((el) => {
      const start = animations.length;
      prepare(el);
      entrances.set(el, animations.slice(start));
    });
    const reveal = (el: Element) => {
      if (seen.has(el)) return;
      seen.add(el);
      entrances.get(el)?.forEach((animation) => {
        if (motion.matches) animation.finish();
        else animation.play();
      });
    };
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          reveal(entry.target);
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -6% 0px", threshold: 0.08 });
    const revealAll = () => {
      targets.forEach(reveal);
      animations.forEach((animation) => animation.finish());
      observer.disconnect();
    };
    // The observer only fires when an element crosses its threshold. A fast
    // scroll, a table-of-contents jump or a background tab can carry an element
    // from below the screen to above it with no crossing, and it would stay
    // invisible for good. So on every scroll (and once now) anything already
    // on screen or scrolled past is revealed too. Content is never left hidden.
    let pending = targets.slice();
    let frame = 0;
    const sweep = () => {
      frame = 0;
      const bottom = window.innerHeight;
      pending = pending.filter((el) => {
        if (el.getBoundingClientRect().top < bottom) {
          reveal(el);
          observer.unobserve(el);
          return false;
        }
        return !seen.has(el);
      });
      if (!pending.length) window.removeEventListener("scroll", onScroll);
    };
    const onScroll = () => { if (!frame) frame = requestAnimationFrame(sweep); };

    if (motion.matches) revealAll();
    else {
      targets.forEach((el) => observer.observe(el));
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll, { passive: true });
      onScroll();
    }

    // Keyboard focus should immediately expose the control and its card.
    const onFocus = (event: FocusEvent) => {
      if (!(event.target instanceof Element)) return;
      let el = event.target.closest("[data-reveal]");
      while (el) {
        reveal(el);
        observer.unobserve(el);
        el = el.parentElement?.closest("[data-reveal]") ?? null;
      }
      animations.forEach((animation) => {
        const target = (animation.effect as KeyframeEffect | null)?.target;
        if (target instanceof Element && target.contains(event.target as Node)) animation.finish();
      });
    };
    const onMotion = () => { if (motion.matches) revealAll(); };
    document.addEventListener("focusin", onFocus);
    motion.addEventListener("change", onMotion);
    return () => {
      observer.disconnect();
      if (frame) cancelAnimationFrame(frame);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      animations.forEach((animation) => animation.cancel());
      document.removeEventListener("focusin", onFocus);
      motion.removeEventListener("change", onMotion);
    };
  }, [pathname]);

  return null;
}
