import { Illustration } from "@/components/ink";

export type PhoneScreen = "scan" | "review" | "reclaim";

// A drawn iPhone showing the app's three moments. Sample data only: it mirrors
// the app's Demo Mode, not anyone's real library.

export function PhoneMock({ screen, className }: { screen: PhoneScreen; className?: string }) {
  return (
    <div
      className={`relative aspect-[9/19] w-full max-w-[300px] rounded-[48px] border-[3px] border-ink bg-ink p-[9px] shadow-[10px_12px_0_var(--mint)] ${className ?? ""}`}
      role="img"
      aria-label={labels[screen]}
    >
      <div className="relative h-full overflow-hidden rounded-[39px] bg-paper">
        <div className="absolute top-2.5 left-1/2 z-10 h-[22px] w-[84px] -translate-x-1/2 rounded-full bg-ink" />
        <div className="flex items-center justify-between px-7 pt-3 text-[10px] font-semibold">
          <span>9:41</span>
          <span className="tracking-tight">●●● ▮</span>
        </div>
        <div className="px-4 pt-6">
          {screen === "scan" && <ScanScreen />}
          {screen === "review" && <ChooseScreen />}
          {screen === "reclaim" && <ReclaimScreen />}
        </div>
      </div>
    </div>
  );
}

const labels: Record<PhoneScreen, string> = {
  scan: "App screen: items that can be made smaller, with the space each would save",
  review: "App screen: choosing a compression level for a video, with the predicted savings",
  reclaim: "App screen: 12.7 GB freed with nothing deleted, originals kept for 30 days",
};

function ScanScreen() {
  const rows = [
    { name: "4K videos", detail: "46 items · 41.2 GB", save: "−29 GB", ill: "ill-video" },
    { name: "Long recordings", detail: "12 items · 9.8 GB", save: "−7 GB", ill: "ill-reset" },
    { name: "Live Photos", detail: "1,840 items · 5.6 GB", save: "−2.7 GB", ill: "ill-photo" },
    { name: "Screenshots", detail: "2,140 items · 6.8 GB", save: "−4.4 GB", ill: "ill-screenshot" },
  ];
  return (
    <div>
      <p className="font-display text-[22px] font-extrabold">Worth shrinking</p>
      <p className="mt-1 text-[11px] text-ink-soft">
        Save up to <span className="font-semibold text-ink">43 GB</span> without deleting
      </p>
      <ul className="mt-4 space-y-2">
        {rows.map((row) => (
          <li key={row.name} className="flex items-center gap-2.5 rounded-2xl border border-hairline bg-surface p-2.5">
            <Illustration name={row.ill} size={32} priority />
            <div className="min-w-0 flex-1">
              <p className="text-[12px] leading-tight font-semibold">{row.name}</p>
              <p className="text-[10px] text-ink-faint">{row.detail}</p>
            </div>
            <span className="rounded-full bg-mint-soft px-1.5 py-0.5 text-[10px] font-bold text-mint-deep">
              {row.save}
            </span>
          </li>
        ))}
      </ul>
      <div className="mt-4 rounded-full bg-ink py-2.5 text-center text-[12px] font-semibold text-paper">
        Start with 4K videos
      </div>
    </div>
  );
}

function ChooseScreen() {
  const levels = [
    { name: "Light", size: "2.9 GB" },
    { name: "Balanced", size: "1.9 GB", selected: true },
    { name: "Maximum", size: "1.2 GB" },
  ];
  return (
    <div>
      <p className="font-display text-[22px] font-extrabold">Concert.MOV</p>
      <p className="mt-1 text-[11px] text-ink-soft">4K · 60 fps · 11 min · 4.2 GB</p>
      <div className="relative mt-3 grid aspect-video place-items-center rounded-xl bg-ink">
        <span className="grid size-9 place-items-center rounded-full bg-paper text-[12px]">▶</span>
        <span className="absolute bottom-1.5 left-2 rounded bg-paper/90 px-1 text-[8px] font-bold">Preview</span>
      </div>
      <div className="mt-3 flex gap-1 rounded-full border border-hairline bg-surface p-1 text-[10px] font-semibold">
        <span className="flex-1 rounded-full bg-ink py-1.5 text-center text-paper">Compress</span>
        <span className="flex-1 py-1.5 text-center">Trim</span>
      </div>
      <ul className="mt-2 space-y-1.5">
        {levels.map((level) => (
          <li
            key={level.name}
            className={`flex items-center justify-between rounded-xl border px-2.5 py-2 text-[11px] ${
              level.selected ? "border-ink bg-mint-soft font-semibold" : "border-hairline bg-surface"
            }`}
          >
            <span>{level.name}</span>
            <span className="tabular-nums">{level.size}</span>
          </li>
        ))}
      </ul>
      <div className="mt-3 rounded-full bg-ink py-2.5 text-center text-[12px] font-semibold text-paper">
        Save 2.3 GB
      </div>
    </div>
  );
}

function ReclaimScreen() {
  return (
    <div className="flex flex-col items-center pt-4 text-center">
      <Illustration name="ill-piggy" size={104} priority />
      <p className="mt-3 font-display text-[34px] leading-none font-extrabold">12.7 GB</p>
      <p className="mt-1 text-[12px] font-semibold text-mint-deep">freed · 0 photos deleted</p>
      <div className="mt-5 w-full rounded-2xl border border-hairline bg-surface p-3 text-left">
        <p className="text-[11px] font-semibold">Originals kept for 30 days</p>
        <p className="mt-0.5 text-[10px] leading-snug text-ink-faint">
          In Recently Deleted, if you want to compare or undo.
        </p>
      </div>
      <div className="mt-2 w-full rounded-2xl border border-hairline bg-surface p-3 text-left">
        <p className="text-[11px] font-semibold">Next up: Live Photos</p>
        <p className="mt-0.5 text-[10px] text-ink-faint">Keep 1,840 as stills · save 2.7 GB</p>
      </div>
    </div>
  );
}
