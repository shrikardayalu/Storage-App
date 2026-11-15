// Checks metadata.json against App Store Connect's limits and the rules that
// make keywords count, then writes metadata.md: a sheet to paste from.
//
//   node marketing/aso/check.mjs
//
// It exits with an error if any field is too long or malformed, and prints
// notes for anything that wastes characters. How Apple's search reads the
// fields (which is what the notes are about):
//   - The name, subtitle and keyword field of ONE localization are pooled,
//     and Apple combines the words in that pool into phrases by itself. So a
//     word needs to appear only once per localization, and a phrase can only
//     be matched if all its words are in the same localization.
//   - A storefront reads several localizations (the US reads ten). Words in
//     different localizations don't combine with each other, but each one
//     still ranks, so repeating a keyword-field word across the localizations
//     of one storefront buys nothing.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const LIMITS = { name: 30, subtitle: 30, keywords: 100 };

// Which localizations each storefront indexes. From Apple's table:
// https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/
// (checked 2026-11-15). Add a storefront here when you start targeting it.
const STOREFRONTS = {
  'United States': ['en-US', 'es-MX', 'fr-FR', 'pt-BR', 'ru', 'ko', 'ar-SA', 'vi', 'zh-Hans', 'zh-Hant'],
  'United Kingdom': ['en-GB'],
  'Canada': ['en-CA', 'fr-CA'],
  'Australia': ['en-AU', 'en-GB'],
};
const LANGUAGE = {
  'en-US': 'English (U.S.)', 'es-MX': 'Spanish (Mexico)', 'fr-FR': 'French', 'pt-BR': 'Portuguese (Brazil)',
  'ru': 'Russian', 'ko': 'Korean', 'ar-SA': 'Arabic', 'vi': 'Vietnamese', 'zh-Hans': 'Chinese (Simplified)',
  'zh-Hant': 'Chinese (Traditional)', 'en-GB': 'English (U.K.)', 'en-CA': 'English (Canada)',
  'fr-CA': 'French (Canada)', 'en-AU': 'English (Australia)',
};
// Words Apple adds for free or ignores, so they waste keyword characters.
const FREE = new Set(['app', 'apps', 'free', 'the', 'a', 'an', 'and', 'for', 'of', 'to', 'in', 'on', 'with', 'my', 'your', 'utilities', 'utility']);
// Apple's own trademarks and competitor names get keyword fields rejected.
const BANNED = ['iphone', 'ipad', 'ios', 'apple', 'icloud', 'whatsapp', 'google', 'cleanup pro', 'swipewipe', 'cleaner kit', 'gemini', 'hyper', 'slidebox'];

const words = s => String(s).toLowerCase().replace(/[^\p{L}\p{N}\s,]/gu, ' ').split(/[\s,]+/).filter(Boolean);
const stem = w => w.length > 3 ? w.replace(/ies$/, 'y').replace(/(?<![su])s$/, '') : w;

const meta = JSON.parse(readFileSync(join(here, 'metadata.json'), 'utf8'));
const locales = meta.locales;
const errors = [], notes = [];

for (const [locale, m] of Object.entries(locales)) {
  if (!LANGUAGE[locale]) errors.push(`${locale}: not a localization this script knows. Add it to LANGUAGE and STOREFRONTS.`);
  for (const [field, max] of Object.entries(LIMITS)) {
    const value = m[field] ?? '';
    if (!value) errors.push(`${locale}: "${field}" is empty.`);
    if ([...value].length > max) errors.push(`${locale}: "${field}" is ${[...value].length} characters, the limit is ${max}: "${value}"`);
  }
  const kw = m.keywords ?? '';
  if (/,\s|\s,/.test(kw)) errors.push(`${locale}: keywords have a space next to a comma. Spaces count toward the 100; write "a,b,c".`);
  if (/^,|,$|,,/.test(kw)) errors.push(`${locale}: keywords have an empty entry (a stray comma).`);
  for (const b of BANNED) if (kw.toLowerCase().split(',').some(k => k === b || k.split(' ').includes(b))) errors.push(`${locale}: "${b}" in keywords is a trademark; Apple rejects those.`);

  const shown = new Set(words(`${m.name} ${m.subtitle}`).map(stem));
  const seen = new Set();
  for (const k of kw.split(',')) {
    for (const w of k.trim().split(/\s+/)) {
      const s = stem(w.toLowerCase());
      if (FREE.has(w.toLowerCase())) notes.push(`${locale}: "${w}" is a word Apple ignores or adds by itself. Drop it from keywords.`);
      else if (shown.has(s)) notes.push(`${locale}: "${w}" is already in the name or subtitle. Drop it from keywords.`);
      else if (seen.has(s)) notes.push(`${locale}: "${w}" appears twice in keywords (plurals count as the same word).`);
      seen.add(s);
    }
  }
  const spare = LIMITS.keywords - [...kw].length;
  if (spare >= 6) notes.push(`${locale}: ${spare} keyword characters unused.`);
  m.pool = new Set([...shown, ...seen]);
  // Every phrase this localization is meant to rank for needs all its words here.
  for (const phrase of m.targets ?? []) {
    const missing = words(phrase).filter(w => !FREE.has(w) && !m.pool.has(stem(w)));
    if (missing.length) errors.push(`${locale}: target "${phrase}" can't be matched; missing ${missing.map(w => `"${w}"`).join(', ')}.`);
  }
}

// Per storefront: wasted repeats, and how much of the research is covered.
const research = existsSync(join(here, 'research', 'data.json')) ? JSON.parse(readFileSync(join(here, 'research', 'data.json'), 'utf8')) : null;
const coverage = [];
for (const [store, list] of Object.entries(STOREFRONTS)) {
  const present = list.filter(l => locales[l]);
  for (const l of list) if (!locales[l]) notes.push(`${store}: no "${l}" (${LANGUAGE[l]}) localization, so its 160 characters go unused.`);
  const owner = new Map();
  for (const l of present) {
    // A repeat is fine when this localization needs the word to complete one of
    // its own target phrases. Otherwise it's filler that another localization already covers.
    const needed = new Set((locales[l].targets ?? []).flatMap(t => words(t).map(stem)));
    for (const w of new Set(words(locales[l].keywords).map(stem))) {
      if (owner.has(w) && !needed.has(w)) notes.push(`${store}: "${w}" is in the keywords of both ${owner.get(w)} and ${l}. ${l} has no target that needs it, so swap it for a new word.`);
      else owner.set(w, l);
    }
  }
  const all = new Set(present.flatMap(l => [...locales[l].pool]));
  const row = { store, locales: present.length, words: all.size, chars: present.reduce((n, l) => n + [...locales[l].keywords].length, 0) };
  if (research) {
    const top = research.phrases.filter(p => p.score >= 20).slice(0, 40);
    const can = p => present.some(l => words(p.phrase).filter(w => !FREE.has(w)).every(w => locales[l].pool.has(stem(w))));
    row.covered = top.filter(can).length; row.of = top.length;
    row.missed = top.filter(p => !can(p)).slice(0, 8).map(p => p.phrase);
  }
  coverage.push(row);
}

for (const n of notes) console.warn(`note: ${n}`);
for (const e of errors) console.error(`error: ${e}`);
console.log('');
for (const c of coverage) {
  console.log(`${c.store}: ${c.locales} localizations, ${c.words} different words, ${c.chars} keyword characters` +
    (c.of ? `, ${c.covered} of the top ${c.of} researched phrases matchable` : ''));
  if (c.missed?.length) console.log(`  not matchable yet: ${c.missed.join('; ')}`);
}
if (errors.length) { console.error(`\n${errors.length} error${errors.length > 1 ? 's' : ''}. Fix metadata.json and run again.`); process.exit(1); }

// The paste sheet.
const len = (s, max) => `${[...s].length}/${max}`;
const sheet = `# App Store metadata, ready to paste

Made by \`check.mjs\` from \`metadata.json\` on ${new Date().toISOString().slice(0, 10)}. Edit the JSON, not this file.

In App Store Connect: your app → the version → the language menu at the top
right → pick (or add) each language below and paste its three fields. The
name and subtitle are under **App Information**; keywords are on the version page.

${Object.entries(STOREFRONTS).map(([store, list]) => `- **${store}** searches: ${list.map(l => LANGUAGE[l]).join(', ')}`).join('\n')}

${Object.entries(locales).map(([locale, m]) => `## ${LANGUAGE[locale]} (\`${locale}\`)

${m.theme ? `Theme: ${m.theme}\n\n` : ''}| Field | Value | Length |
|---|---|---|
| Name | ${m.name} | ${len(m.name, 30)} |
| Subtitle | ${m.subtitle} | ${len(m.subtitle, 30)} |

Keywords (${len(m.keywords, 100)}):

\`\`\`
${m.keywords}
\`\`\`
${m.targets?.length ? `\nPhrases this is built to match: ${m.targets.join('; ')}.\n` : ''}`).join('\n')}`;
writeFileSync(join(here, 'metadata.md'), sheet);
console.log(`\nAll within limits. Paste sheet: ${join(here, 'metadata.md')}`);
