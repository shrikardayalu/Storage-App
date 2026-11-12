import type { Token, Tokens } from "marked";
import type { Competitor } from "@/lib/comparisons";
import { siteConfig } from "@/lib/site";

type Status = "included" | "unavailable" | "unknown" | "benefit" | "detail";

// Explicit editorial cues: "not advertised" is unknown, never an absent feature.
const comparisonRows: Record<string, Record<string, [Status, Status]>> = {
  cleanup: {
    "Finds duplicates and similar photos": ["included", "included"],
    "Old screenshots": ["benefit", "included"],
    "Video compression": ["benefit", "included"],
    "Trim long videos": ["benefit", "unknown"],
    "Live Photos to stills": ["benefit", "unknown"],
    "Best shot of each burst": ["benefit", "unknown"],
    "Big files in the Files app": ["benefit", "unknown"],
    "Contacts and email cleanup": ["unavailable", "included"],
    "Private photo vault": ["unavailable", "included"],
    "Shows the space you actually got back": ["benefit", "unknown"],
    "Free trial": ["benefit", "detail"],
    "Paid plans (US)": ["detail", "detail"],
    "Privacy label": ["benefit", "detail"],
    "Requires": ["detail", "detail"],
  },
  "clever-cleaner": {
    "Similar and duplicate photos": ["included", "included"],
    "Video compression": ["benefit", "included"],
    "Trim long videos": ["benefit", "unknown"],
    "Live Photos to stills": ["included", "included"],
    "Screenshot re-save or compression": ["included", "included"],
    "One-tap cleanup": ["included", "included"],
    "Swipe to delete": ["included", "included"],
    "Best shot of each burst": ["benefit", "unknown"],
    "Big files in the Files app": ["benefit", "unknown"],
    "Guides for WhatsApp, Messages, Safari": ["benefit", "unavailable"],
    "Measures the space you got back": ["benefit", "detail"],
    "Free tier": ["benefit", "detail"],
    "Paid plans (US)": ["detail", "detail"],
    "Privacy label": ["benefit", "detail"],
    "Requires": ["detail", "detail"],
  },
  "cleanmy-phone": {
    "Duplicates and similar photos": ["benefit", "included"],
    "Blurry and black shots": ["benefit", "included"],
    "Large videos and screenshots": ["included", "included"],
    "Video compression": ["included", "included"],
    "Trim long videos": ["benefit", "unknown"],
    "Live Photos to stills": ["included", "included"],
    "Screenshot re-save": ["benefit", "unknown"],
    "Best shot of each burst": ["benefit", "unknown"],
    "AI categories (people, pets, travel)": ["unavailable", "included"],
    "Contacts and email cleanup": ["unavailable", "included"],
    "Big files in the Files app": ["benefit", "unknown"],
    "Measures the space you got back": ["benefit", "detail"],
    "Paid plans (US)": ["detail", "detail"],
    "Privacy label": ["benefit", "detail"],
    "Requires": ["detail", "detail"],
  },
  "cleaner-kit": {
    "Duplicates, similar, and blurry photos": ["included", "included"],
    "Swipe to delete": ["included", "included"],
    "Video compression": ["benefit", "included"],
    "Trim long videos": ["benefit", "unknown"],
    "Live Photos to stills": ["included", "included"],
    "Screenshot re-save": ["benefit", "unknown"],
    "Bursts": ["benefit", "included"],
    "Contacts and email cleanup": ["unavailable", "included"],
    "Secret folder": ["unavailable", "included"],
    "Big files in the Files app": ["benefit", "unknown"],
    "Space freed": ["benefit", "detail"],
    "Ads": ["benefit", "detail"],
    "Paid plans (US)": ["detail", "detail"],
    "Privacy label": ["benefit", "detail"],
    "Requires": ["detail", "detail"],
  },
  swipewipe: {
    "Swipe to delete": ["included", "included"],
    "Free swiping": ["benefit", "detail"],
    "Finds duplicates automatically": ["included", "included"],
    "Blurry and black shots, receipts, documents": ["benefit", "included"],
    "Video compression and trimming": ["included", "included"],
    "Live Photos to stills": ["benefit", "unknown"],
    "Screenshot re-save": ["benefit", "unknown"],
    "Best shot of each burst": ["benefit", "unknown"],
    "Big files in the Files app": ["benefit", "unavailable"],
    "Space freed": ["benefit", "detail"],
    "On This Day, streaks, widgets": ["unavailable", "included"],
    "Paid plans (US)": ["detail", "detail"],
    "Privacy label": ["benefit", "detail"],
    "Requires": ["detail", "detail"],
  },
  slidebox: {
    "Main job": ["detail", "detail"],
    "Finds duplicates automatically": ["benefit", "unavailable"],
    "Blurry and black shots, receipts, old screenshots": ["benefit", "unavailable"],
    "Sorted biggest first": ["benefit", "unavailable"],
    "File photos into albums": ["unavailable", "included"],
    "Video compression and trimming": ["benefit", "unknown"],
    "Live Photos to stills": ["benefit", "unknown"],
    "Screenshot re-save": ["benefit", "unavailable"],
    "Best shot of each burst": ["benefit", "unknown"],
    "Big files in the Files app": ["benefit", "unavailable"],
    "Measures the space you got back": ["benefit", "unavailable"],
    "Paid plans (US)": ["detail", "detail"],
    "Privacy label": ["benefit", "detail"],
    "Requires": ["detail", "detail"],
  },
};

function statusIcon(status: Status) {
  if (status === "detail") return "";
  const mark = status === "unknown" ? "?" : status === "unavailable" ? "−" : "✓";
  return `<span class="comparison-icon comparison-icon--${status}" aria-hidden="true">${mark}</span>`;
}

export function createComparisonTableRenderer(competitor: Competitor) {
  const statusesByFeature = comparisonRows[competitor.slug] ?? {};
  const keyId = `comparison-${competitor.slug}-key`;

  return function renderComparisonTable(table: Tokens.Table, inline: (tokens: Token[]) => string) {
    const header = table.header
      .map((cell, index) => `<th scope="col">${index === 0 ? "Feature" : inline(cell.tokens)}</th>`)
      .join("");
    const rows = table.rows.map((row) => {
      const statuses = statusesByFeature[row[0].text] ?? ["detail", "detail"];
      const cells = row.slice(1).map((cell, index) => {
        const status = statuses[index];
        return `<td data-status="${status}"><span class="comparison-value">${statusIcon(status)}<span>${inline(cell.tokens)}</span></span></td>`;
      }).join("");
      return `<tr><th scope="row">${inline(row[0].tokens)}</th>${cells}</tr>`;
    }).join("");

    return `<div class="comparison-table">
    <div class="comparison-key" id="${keyId}">
      <span>${statusIcon("benefit")}<span>${siteConfig.name} advantage</span></span>
      <span>${statusIcon("unknown")}<span>Not advertised</span></span>
    </div>
    <div class="table-scroll" role="region" aria-label="${siteConfig.name} vs ${competitor.name} feature comparison" tabindex="0">
      <table aria-describedby="${keyId}"><thead><tr>${header}</tr></thead><tbody>${rows}</tbody></table>
    </div>
  </div>\n`;
  };
}
