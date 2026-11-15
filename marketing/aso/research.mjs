// Keyword research against competitor apps, from Apple's public endpoints only.
// No account, no API key, no npm packages (Node 22+).
//
//   node marketing/aso/research.mjs              full run (about 5 minutes the first time)
//   node marketing/aso/research.mjs --fresh      ignore the cache and fetch everything again
//   node marketing/aso/research.mjs --quick      seeds only, no autocomplete expansion
//
// What it does, for every seed in research/seeds.json:
//   1. Asks App Store autocomplete what people type after the seed, in each
//      storefront. A phrase Apple suggests is a phrase people search for.
//   2. Searches the primary storefront for the seed and for the suggested
//      phrases, and records the top 10 apps: who they are, how many ratings
//      they have, and whether the phrase is in their title.
//   3. Reads the subtitle of each competitor from its App Store page.
//
// It writes research/data.json (everything) and research/report.md (the
// readable version). Responses are cached in research/cache/ for 7 days.
//
// Limits worth knowing: Apple publishes search volume only inside Apple Ads,
// so "demand" here is a proxy (is it an autocomplete suggestion, and how
// high). The iTunes Search API order is close to App Store search order but
// not identical.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dir = join(here, 'research');
const cacheDir = join(dir, 'cache');
mkdirSync(cacheDir, { recursive: true });

const args = process.argv.slice(2);
const FRESH = args.includes('--fresh'), QUICK = args.includes('--quick');
const MAX_SEARCHES = 90, TOP = 10, CACHE_DAYS = 7;
// Storefront ids for the autocomplete endpoint.
const FRONT = { us: 143441, gb: 143444, ca: 143455, au: 143460 };
// Words that carry no search meaning; Apple ignores most of them.
const STOP = new Set(('a an and app apps at by for from in is it my of on or the to up with your you & - : + ' +
  'iphone ipad ios phone').split(' '));

const config = JSON.parse(readFileSync(join(dir, 'seeds.json'), 'utf8'));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const words = s => s.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean);
const stem = w => w.length > 3 ? w.replace(/(ies)$/, 'y').replace(/(?<![su])s$/, '') : w;

let lastCall = 0;
/** Fetches text, at most one request per `gap` ms, cached on disk. */
async function get(url, { gap, headers = {} }) {
  const file = join(cacheDir, createHash('sha1').update(url + JSON.stringify(headers)).digest('hex') + '.txt');
  if (!FRESH && existsSync(file) && Date.now() - statSync(file).mtimeMs < CACHE_DAYS * 864e5) return readFileSync(file, 'utf8');
  for (let attempt = 1; ; attempt++) {
    await sleep(Math.max(0, lastCall + gap - Date.now()));
    lastCall = Date.now();
    try {
      const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0', ...headers } });
      if (res.ok) { const text = await res.text(); writeFileSync(file, text); return text; }
      if (attempt >= 4) throw new Error(`HTTP ${res.status}`);
      await sleep(res.status === 403 || res.status === 429 ? 30000 : 3000);   // rate limited: wait it out
    } catch (e) {
      if (attempt >= 4) { console.warn(`  gave up on ${url}: ${e.message}`); return null; }
    }
  }
}

/** What autocomplete suggests for a term, best first. */
async function hints(term, country) {
  const xml = await get(
    `https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?clientApplication=Software&term=${encodeURIComponent(term)}`,
    { gap: 400, headers: { 'X-Apple-Store-Front': `${FRONT[country]}-1,29` } });
  return xml ? [...xml.matchAll(/<key>term<\/key>\s*<string>([^<]*)<\/string>/g)].map(m => m[1].toLowerCase().trim()) : [];
}

/** The top apps for a term in a storefront. */
async function search(term, country) {
  const text = await get(
    `https://itunes.apple.com/search?term=${encodeURIComponent(term)}&country=${country}&entity=software&limit=${TOP}`,
    { gap: 3200 });   // the Search API allows about 20 calls a minute
  try {
    return JSON.parse(text).results.map(r => ({
      id: r.trackId, title: r.trackName, ratings: r.userRatingCount ?? 0, seller: r.sellerName,
      genre: r.primaryGenreName, url: r.trackViewUrl.replace(/\?.*/, ''),
    }));
  } catch { return []; }
}

/** The subtitle shown under the app's name on its App Store page. */
async function subtitle(app) {
  const html = await get(app.url, { gap: 900 });
  const m = html?.match(/class="subtitle[^"]*"[^>]*>([^<]+)</);
  return m ? m[1].replace(/&amp;/g, '&').replace(/&#x27;|&#39;/g, "'").trim() : '';
}

const isRelevant = phrase =>
  config.relevant.some(r => phrase.includes(r)) && !config.irrelevant.some(r => phrase.includes(r));

// 1. Autocomplete, per storefront.
console.log(`Autocomplete for ${config.seeds.length} seeds in ${config.storefronts.join(', ')}...`);
const phrases = new Map();   // phrase -> { seed, suggested: { us: position, ... } }
const note = (phrase, seed) => phrases.get(phrase) ?? phrases.set(phrase, { phrase, seed, isSeed: phrase === seed, suggested: {} }).get(phrase);
for (const seed of config.seeds) {
  note(seed, seed);
  for (const country of config.storefronts) {
    const list = await hints(seed, country);
    list.forEach((term, i) => {
      // Autocomplete also suggests app names ("hafif: screenshot cleaner"); punctuation gives them away.
      if (/[^a-z0-9 ]/.test(term) || !isRelevant(term) || words(term).length > 4) return;
      const p = note(term, seed);
      p.suggested[country] = Math.min(p.suggested[country] ?? 99, i + 1);
    });
  }
}

// 2. Search the primary storefront. Seeds first, then suggestions seen in the most storefronts.
const queue = [...phrases.values()]
  .filter(p => p.isSeed || !QUICK)
  .sort((a, b) => b.isSeed - a.isSeed || Object.keys(b.suggested).length - Object.keys(a.suggested).length
    || (a.suggested[config.primary] ?? 99) - (b.suggested[config.primary] ?? 99))
  .slice(0, MAX_SEARCHES);
console.log(`Searching ${queue.length} phrases in "${config.primary}" (about ${Math.ceil(queue.length * 3.2 / 60)} minutes uncached)...`);
const apps = new Map();
for (const [i, p] of queue.entries()) {
  const results = await search(p.phrase, config.primary);
  const need = words(p.phrase).filter(w => !STOP.has(w)).map(stem);
  p.top = results.map(r => r.id);
  // How many of the top apps already target this phrase in their title.
  p.inTitle = results.filter(r => { const t = new Set(words(r.title).map(stem)); return need.every(w => t.has(w)); }).length;
  const counts = results.map(r => r.ratings).sort((a, b) => a - b);
  p.medianRatings = counts.length ? counts[Math.floor(counts.length / 2)] : 0;
  // A suggestion that is just the name of the app ranked first is a brand search, not a keyword.
  const brand = (results[0]?.title ?? '').toLowerCase().split(/\s*[:\-–|]\s*/)[0].replace(/[^a-z0-9 ]/g, '').trim();
  p.brand = !p.isSeed && brand === p.phrase;
  for (const r of results) {
    const app = apps.get(r.id) ?? apps.set(r.id, { ...r, appearances: 0, phrases: [] }).get(r.id);
    app.appearances++; app.phrases.push(p.phrase);
  }
  if ((i + 1) % 10 === 0) console.log(`  ${i + 1} of ${queue.length}`);
}

// 3. Subtitles of the competitors that show up most.
const competitors = [...apps.values()].sort((a, b) => b.appearances - a.appearances || b.ratings - a.ratings).slice(0, 40);
console.log(`Reading subtitles of ${competitors.length} competitors...`);
for (const app of competitors) app.subtitle = await subtitle(app);

// Score. Demand: is it an autocomplete suggestion, in how many storefronts, how high.
// Difficulty: how many of the top 10 have it in the title, and how big they are.
for (const p of queue) {
  const fronts = Object.keys(p.suggested).length;
  const best = Math.min(99, ...Object.values(p.suggested));
  p.demand = Math.round(Math.min(100, (p.isSeed ? 35 : 0) + fronts * 12 + (fronts ? Math.max(0, 11 - best) * 2.5 : 0)));
  p.difficulty = Math.round(Math.min(100, p.inTitle * 6 + Math.log10(p.medianRatings + 1) * 8));
  p.score = Math.round(p.demand * (1 - p.difficulty / 140));
}
queue.sort((a, b) => b.score - a.score);
const ranked = queue.filter(p => !p.brand);

// Which single words competitors put in their title and subtitle.
const wordStats = new Map();
for (const app of competitors) {
  const seen = new Set(words(`${app.title} ${app.subtitle}`).filter(w => !STOP.has(w) && w.length > 2));
  const inTitle = new Set(words(app.title));
  for (const w of seen) {
    const s = wordStats.get(w) ?? wordStats.set(w, { word: w, apps: 0, titles: 0 }).get(w);
    s.apps++; if (inTitle.has(w)) s.titles++;
  }
}
const wordList = [...wordStats.values()].filter(w => w.apps >= 2).sort((a, b) => b.apps - a.apps);

const date = new Date().toISOString().slice(0, 10);
writeFileSync(join(dir, 'data.json'), JSON.stringify({
  date, storefronts: config.storefronts, primary: config.primary,
  phrases: ranked.map(({ top, brand, ...p }) => p), words: wordList,
  competitors: competitors.map(({ phrases: ph, ...a }) => ({ ...a, phrases: ph.length })),
}, null, 2) + '\n');

const fmt = n => n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : String(n);
const where = p => config.storefronts.map(c => p.suggested[c] ? `${c} #${p.suggested[c]}` : null).filter(Boolean).join(', ') || 'not suggested';
const report = `# Keyword research

Run on ${date} against the ${config.primary.toUpperCase()} App Store, with autocomplete from ${config.storefronts.map(c => c.toUpperCase()).join(', ')}.
Made by \`research.mjs\`; don't edit by hand, run it again.

How to read it:

- **Demand** (0 to 100) is a proxy, because Apple shares real search volume only inside Apple Ads. A phrase scores higher when App Store autocomplete suggests it, in more storefronts, nearer the top.
- **Difficulty** (0 to 100) rises with how many of the top ${TOP} apps already have the phrase in their title, and with how many ratings those apps have.
- **Score** is demand, discounted by difficulty. High score: people search it and the results are beatable.

## Phrases, best first

| Phrase | Score | Demand | Difficulty | Top ${TOP} with it in the title | Median ratings of top ${TOP} | Autocomplete |
|---|---|---|---|---|---|---|
${ranked.map(p => `| ${p.phrase} | ${p.score} | ${p.demand} | ${p.difficulty} | ${p.inTitle} | ${fmt(p.medianRatings)} | ${where(p)} |`).join('\n')}

## Words competitors use

Out of ${competitors.length} competitors, how many use each word in their title or subtitle.

| Word | Apps | In the title |
|---|---|---|
${wordList.slice(0, 60).map(w => `| ${w.word} | ${w.apps} | ${w.titles} |`).join('\n')}

## Competitors

The apps that appear most often in the top ${TOP} across all the phrases searched.

| App | Subtitle | Ratings | Phrases ranked for |
|---|---|---|---|
${competitors.map(a => `| [${a.title.replace(/\|/g, '/')}](${a.url}) | ${(a.subtitle || '').replace(/\|/g, '/')} | ${fmt(a.ratings)} | ${a.phrases.length} |`).join('\n')}
`;
writeFileSync(join(dir, 'report.md'), report);
console.log(`Done: ${ranked.length} phrases, ${competitors.length} competitors.\n  ${join(dir, 'report.md')}`);
