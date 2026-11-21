import fs from "node:fs";
import path from "node:path";

// Shared Open Graph artwork: what people see when a link is shared in
// Messages, WhatsApp, Slack, X and so on. Rendered by next/og (Satori), so
// inline styles and flexbox only, and fonts must be loaded explicitly or it
// falls back to a generic sans. The fonts here are the site's own
// (Schibsted Grotesk, Hanken Grotesk, Gochi Hand), as static latin .woff files.

const fontDir = path.join(process.cwd(), "src", "components", "og", "fonts");
const readFont = (file: string) => fs.readFileSync(path.join(fontDir, file));

export const ogSize = { width: 1200, height: 630 };

export const ogFonts = [
  { name: "Schibsted", data: readFont("SchibstedGrotesk-ExtraBold.woff"), weight: 800 as const, style: "normal" as const },
  { name: "Hanken", data: readFont("HankenGrotesk-Medium.woff"), weight: 500 as const, style: "normal" as const },
  { name: "Hanken", data: readFont("HankenGrotesk-Bold.woff"), weight: 700 as const, style: "normal" as const },
  { name: "Gochi", data: readFont("GochiHand-Regular.woff"), weight: 400 as const, style: "normal" as const },
];

/** Options to pass straight to `new ImageResponse(element, ogOptions)`. */
export const ogOptions = { ...ogSize, fonts: ogFonts };

const dataUri = (file: string, type: string) =>
  `data:${type};base64,${fs.readFileSync(path.join(process.cwd(), "public", file)).toString("base64")}`;

const logo = dataUri("logo.png", "image/png");
const illustration = (name: string) => dataUri(`illustrations/${name}.svg`, "image/svg+xml");

const c = {
  paper: "#F4F1EA",
  surface: "#FFFDF8",
  ink: "#1A1A17",
  inkSoft: "#55534C",
  mint: "#5ED49B",
  mintSoft: "#CDEFDC",
  mintDeep: "#1C7D50",
  tomato: "#EF6A4C",
};

function Scribble({ width }: { width: number }) {
  return (
    <svg width={width} height={22} viewBox="0 0 300 24" preserveAspectRatio="none">
      <path
        d="M4 15c40-7 92-11 146-10 52 1 98 4 146 9M22 20c58-5 132-7 236-3"
        fill="none"
        stroke={c.mint}
        strokeWidth="6"
        strokeLinecap="round"
      />
    </svg>
  );
}

function Sparks({ size, color }: { size: number; color: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 40 40">
      <path d="M20 3v9M4 14l7 5M36 14l-7 5" stroke={color} strokeWidth="3.4" strokeLinecap="round" fill="none" />
    </svg>
  );
}

function InkArrow() {
  // Curly arrow, pointing down-right toward the card.
  return (
    <svg width={96} height={72} viewBox="0 0 120 90" style={{ transform: "scaleX(-1)" }}>
      <path
        d="M112 8c-22 4-44 16-52 34-6 14 6 22 14 14 8-9-6-20-22-14-18 7-30 24-38 40"
        fill="none"
        stroke={c.ink}
        strokeWidth="3.6"
        strokeLinecap="round"
      />
      <path d="M10 58l3 25 22-11" fill="none" stroke={c.ink} strokeWidth="3.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function OgCard({
  eyebrow,
  title,
  highlight,
  note,
  art = "ill-phone-sparkle",
  footer = "simpleshrink.com",
}: {
  /** Small handwritten line above the title. */
  eyebrow: string;
  title: string;
  /** Optional last line of the title, set on its own line with a marker underline. */
  highlight?: string;
  /** Handwritten aside next to the illustration. */
  note: string;
  /** Illustration name from public/illustrations (light variant). */
  art?: string;
  footer?: string;
}) {
  const length = title.length + (highlight?.length ?? 0);
  const baseSize = length > 70 ? 54 : length > 48 ? 62 : length > 30 ? 74 : 92;
  // The highlight sits on one line, so shrink the whole title until it fits the column.
  const titleSize = highlight ? Math.min(baseSize, Math.floor(630 / (highlight.length * 0.56))) : baseSize;

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        position: "relative",
        background: c.paper,
        backgroundImage: `radial-gradient(circle at 82% 46%, ${c.mintSoft} 0%, rgba(205,239,220,0) 46%)`,
        fontFamily: "Hanken",
        color: c.ink,
      }}
    >
      {/* Left: brand, title, footer */}
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          width: 720,
          padding: "56px 0 52px 72px",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={logo} width={58} height={58} style={{ borderRadius: 15, border: `3px solid ${c.ink}` }} alt="" />
          <span style={{ fontFamily: "Schibsted", fontWeight: 800, fontSize: 34, letterSpacing: -1 }}>SimpleShrink</span>
        </div>

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
            <Sparks size={34} color={c.mintDeep} />
            <span style={{ fontFamily: "Gochi", fontSize: 36, color: c.mintDeep }}>{eyebrow}</span>
          </div>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              fontFamily: "Schibsted",
              fontWeight: 800,
              fontSize: titleSize,
              lineHeight: 0.98,
              letterSpacing: titleSize > 70 ? -3.5 : -2.5,
            }}
          >
            <span>{title}</span>
            {highlight ? (
              <div style={{ display: "flex", flexDirection: "column", alignSelf: "flex-start" }}>
                <span>{highlight}</span>
                <div style={{ display: "flex", marginTop: -4 }}>
                  <Scribble width={Math.min(630, highlight.length * titleSize * 0.52)} />
                </div>
              </div>
            ) : (
              <div style={{ display: "flex", marginTop: 14 }}>
                <Scribble width={220} />
              </div>
            )}
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 12, fontSize: 26, fontWeight: 700, color: c.inkSoft }}>
          <div style={{ width: 16, height: 16, borderRadius: 8, background: c.mint, border: `3px solid ${c.ink}` }} />
          {footer}
        </div>
      </div>

      {/* Right: tilted card with the illustration and a handwritten aside */}
      <div style={{ display: "flex", flex: 1, position: "relative" }}>
        <div
          style={{
            position: "absolute",
            top: 150,
            left: 60,
            width: 330,
            height: 360,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            background: c.surface,
            border: `4px solid ${c.ink}`,
            borderRadius: 40,
            boxShadow: `14px 14px 0 ${c.mint}`,
            transform: "rotate(4deg)",
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={illustration(art)} width={240} height={240} alt="" />
        </div>
        <div
          style={{
            position: "absolute",
            top: 40,
            right: 44,
            display: "flex",
            alignItems: "flex-end",
            transform: "rotate(-5deg)",
          }}
        >
          <span
            style={{
              fontFamily: "Gochi",
              fontSize: 36,
              lineHeight: 1,
              textAlign: "right",
              color: c.tomato,
              maxWidth: 420,
            }}
          >
            {note}
          </span>
          <div style={{ display: "flex", marginLeft: 4, marginBottom: -44 }}>
            <InkArrow />
          </div>
        </div>
      </div>
    </div>
  );
}
