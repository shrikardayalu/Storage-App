import fs from "node:fs";
import path from "node:path";

// Shared Open Graph artwork (rendered by next/og, so inline styles only).
const logo = `data:image/png;base64,${fs
  .readFileSync(path.join(process.cwd(), "public", "logo.png"))
  .toString("base64")}`;

export const ogSize = { width: 1200, height: 630 };

export function OgCard({ eyebrow, title, footer }: { eyebrow: string; title: string; footer: string }) {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        background: "#F4F1EA",
        padding: 48,
      }}
    >
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#FFFDF8",
          border: "4px solid #1A1A17",
          borderRadius: 40,
          boxShadow: "14px 14px 0 #5ED49B",
          padding: "56px 64px",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={logo} width={64} height={64} style={{ borderRadius: 16, border: "3px solid #1A1A17" }} alt="" />
          <span style={{ fontSize: 30, fontWeight: 700, color: "#1C7D50" }}>{eyebrow}</span>
        </div>
        <div
          style={{
            fontSize: title.length > 60 ? 62 : 74,
            fontWeight: 800,
            lineHeight: 1.04,
            letterSpacing: -2,
            color: "#1A1A17",
          }}
        >
          {title}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 14, fontSize: 26, color: "#55534C" }}>
          <div style={{ width: 18, height: 18, borderRadius: 9, background: "#5ED49B", border: "3px solid #1A1A17" }} />
          {footer}
        </div>
      </div>
    </div>
  );
}
