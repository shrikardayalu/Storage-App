// Renders App Store screenshot sets at Apple's sizes. No npm packages: it
// drives headless Chrome through its DevTools port (Node 22+), like
// ../../carousels/render.mjs. Needs an internet connection for the fonts.
//
//   node marketing/aso/screenshots/render.mjs control          one set
//   node marketing/aso/screenshots/render.mjs --all            every set in sets/
//   node marketing/aso/screenshots/render.mjs control --size all     every size (default: 6.9 and 6.5)
//   node marketing/aso/screenshots/render.mjs control --size 6.9
//   node marketing/aso/screenshots/render.mjs control --check  validate only
//
// Output: out/<set>/<locale>/<size>/01.png ... plus out/<set>/overview.png.
// See ../README.md for the set format.
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const assets = join(here, '..', '..', 'app-store');   // screens/ and art/ are shared with the carousels
const PORT = 9379;

// Portrait sizes App Store Connect accepts for each iPhone display class.
// 6.9" is the one Apple asks for; it scales that down for every smaller
// phone unless you upload the others. 6.5" is the accepted alternative.
const SIZES = {
  '6.9': { w: 1320, h: 2868, name: 'iPhone 6.9" (16/17 Pro Max)' },
  '6.5': { w: 1284, h: 2778, name: 'iPhone 6.5" (11 Pro Max to 14 Plus)' },
  '6.3': { w: 1206, h: 2622, name: 'iPhone 6.3" (16/17 Pro)' },
  '6.1': { w: 1170, h: 2532, name: 'iPhone 6.1" (12 to 14, 16e)' },
};
const DEFAULT_SIZES = ['6.9', '6.5'];
const LAYOUTS = { phone: ['headline', 'screen'], hang: ['headline', 'screen'], promises: ['headline', 'items'] };
const THEMES = ['cream', 'mint', 'soft', 'dark'];

const args = process.argv.slice(2);
const flag = name => args.includes(name);
const fail = message => { console.error(message); process.exit(1); };
const sizeArg = flag('--size') ? args[args.indexOf('--size') + 1] : null;
const sizes = !sizeArg ? DEFAULT_SIZES : sizeArg === 'all' ? Object.keys(SIZES) : sizeArg.split(',');
for (const s of sizes) if (!SIZES[s]) fail(`Unknown size "${s}". Use ${Object.keys(SIZES).join(', ')} or all.`);
const all = readdirSync(join(here, 'sets')).filter(f => f.endsWith('.json')).map(f => f.slice(0, -5));
const names = flag('--all') ? all : args.filter(a => !a.startsWith('--') && a !== sizeArg).map(a => a.replace(/\.json$/, ''));
if (!names.length) fail(`Give a set name (${all.join(', ')}) or --all.`);

/** Reads a set, checks it, and returns one list of shots per locale. */
function load(name) {
  const errors = [], warnings = [];
  const file = join(here, 'sets', `${name}.json`);
  if (!existsSync(file)) return { errors: [`No set at ${file}. Sets: ${all.join(', ')}.`], warnings };
  let set;
  try { set = JSON.parse(readFileSync(file, 'utf8')); } catch (e) { return { errors: [`Not valid JSON: ${e.message}`], warnings }; }
  const shots = Array.isArray(set.shots) ? set.shots : [];
  if (shots.length < 1 || shots.length > 10) errors.push(`App Store Connect takes 1 to 10 screenshots, this set has ${shots.length}.`);

  const check = (s, where) => {
    if (!LAYOUTS[s.layout]) return errors.push(`${where}: unknown layout "${s.layout}". Use ${Object.keys(LAYOUTS).join(', ')}.`);
    if (!THEMES.includes(s.theme)) errors.push(`${where}: unknown theme "${s.theme}". Use ${THEMES.join(', ')}.`);
    for (const key of LAYOUTS[s.layout]) if (!s[key] || s[key].length === 0) errors.push(`${where}: missing "${key}".`);
    if (s.screen && !existsSync(join(assets, 'screens', `${s.screen}.png`))) errors.push(`${where}: no screen at ${join(assets, 'screens', `${s.screen}.png`)}`);
    for (const a of s.art ?? []) {
      const f = `ill-${a}${s.theme === 'dark' ? '-dark' : ''}.svg`;
      if (!existsSync(join(assets, 'art', f))) errors.push(`${where}: no illustration at ${join(assets, 'art', f)}`);
    }
    const lines = String(s.headline ?? '').split('\n');
    if (lines.length > 3) warnings.push(`${where}: the headline has ${lines.length} lines; three is the most that reads at thumbnail size.`);
  };
  shots.forEach((s, i) => check(s, `Shot ${i + 1}`));

  // Other locales reuse the shots and override only what they list (usually "headline").
  const locales = { 'en-US': shots };
  for (const [locale, overrides] of Object.entries(set.locales ?? {})) {
    if (!Array.isArray(overrides) || overrides.length !== shots.length) { errors.push(`locales.${locale} needs ${shots.length} entries, one per shot (use {} to keep a shot as it is).`); continue; }
    locales[locale] = shots.map((s, i) => ({ ...s, ...overrides[i] }));
    locales[locale].forEach((s, i) => check(s, `${locale} shot ${i + 1}`));
  }
  return { locales, errors, warnings };
}

const loaded = names.map(name => ({ name, ...load(name) }));
let broken = false;
for (const { name, errors, warnings } of loaded) {
  for (const w of warnings) console.warn(`${name}: note: ${w}`);
  for (const e of errors) { console.error(`${name}: error: ${e}`); broken = true; }
}
if (broken) fail('Fix the errors above, then render again.');
if (flag('--check')) { console.log('Looks fine.'); process.exit(0); }

const CHROME = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome', '/usr/bin/chromium',
].find(p => p && existsSync(p));
if (!CHROME) fail('Could not find Chrome or Edge. Set CHROME to the browser path.');

const profile = mkdtempSync(join(tmpdir(), 'aso-chrome-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, '--hide-scrollbars',
  '--force-device-scale-factor=1', `--user-data-dir=${profile}`, 'about:blank',
], { stdio: 'ignore' });

try {
  let page;
  for (let i = 0; i < 100 && !page; i++) {
    await new Promise(r => setTimeout(r, 200));
    try { page = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
  }
  if (!page) throw new Error('The browser did not start.');

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((ok, no) => { ws.onopen = ok; ws.onerror = no; });
  let id = 0;
  const waiting = new Map(), events = new Map();
  ws.onmessage = m => {
    const msg = JSON.parse(m.data);
    if (msg.id) { const w = waiting.get(msg.id); waiting.delete(msg.id); msg.error ? w.no(new Error(msg.error.message)) : w.ok(msg.result); }
    else events.get(msg.method)?.(msg.params);
  };
  const send = (method, params = {}) => new Promise((ok, no) => { waiting.set(++id, { ok, no }); ws.send(JSON.stringify({ id, method, params })); });
  const run = async expression => {
    const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
    return r.result.value;
  };
  const shoot = async (w, h, path) => {
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    const { data } = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(path, Buffer.from(data, 'base64'));
  };

  await send('Page.enable');
  const ready = new Promise(ok => events.set('Page.loadEventFired', ok));
  await send('Page.navigate', { url: pathToFileURL(join(here, 'template.html')).href });
  await ready;
  const assetsUrl = JSON.stringify(pathToFileURL(assets).href);

  for (const { name, locales } of loaded) {
    const out = join(here, 'out', name);
    rmSync(out, { recursive: true, force: true });
    let count = 0;
    for (const [locale, shots] of Object.entries(locales)) {
      for (const size of sizes) {
        const { w, h } = SIZES[size], folder = join(out, locale, size);
        mkdirSync(folder, { recursive: true });
        for (let i = 0; i < shots.length; i++) {
          const [scale] = await run(`draw(${JSON.stringify([shots[i]])}, ${assetsUrl}, ${w}, ${h}, false)`);
          if (scale < 0.8 && size === sizes[0]) console.warn(`${name}: note: ${locale} shot ${i + 1}: the headline was shrunk to ${Math.round(scale * 100)}% to fit. Shorten the longest line.`);
          await shoot(w, h, join(folder, `${String(i + 1).padStart(2, '0')}.png`));
          count++;
        }
      }
      // A contact sheet per locale, for a quick look and for comparing sets.
      const n = shots.length;
      await run(`draw(${JSON.stringify(shots)}, ${assetsUrl}, 1320, 2868, true)`);
      await shoot(Math.ceil((n * 1320 + (n + 1) * 60) * 0.22), Math.ceil((2868 + 120) * 0.22),
        join(out, locale === 'en-US' ? 'overview.png' : `overview-${locale}.png`));
    }
    console.log(`${name}: ${count} images (${Object.keys(locales).join(', ')} at ${sizes.map(s => `${SIZES[s].w}x${SIZES[s].h}`).join(', ')}) in ${out}`);
  }
  ws.close();
} finally {
  chrome.kill();
  await new Promise(r => setTimeout(r, 300));
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
}
