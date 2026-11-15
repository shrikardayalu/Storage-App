// Renders carousel JSON files into slide images for TikTok (1080 x 1920) and
// Instagram (1080 x 1350). No npm packages: it drives headless Chrome through
// its DevTools port (Node 22+), like ../app-store/preview/render.mjs.
//
//   node marketing/carousels/render.mjs marketing/carousels/carousels/<name>.json
//   node marketing/carousels/render.mjs --all
//   node marketing/carousels/render.mjs <file> --format tiktok   (or instagram)
//   node marketing/carousels/render.mjs <file> --check           (validate only)
//
// Output goes to out/<name>/ (git-ignored). See README.md for the JSON format.
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const FORMATS = { tiktok: { w: 1080, h: 1920 }, instagram: { w: 1080, h: 1350 } };
const PORT = 9378;

// Required fields and the longest copy that still reads well, per slide type.
const TYPES = {
  hook:   { required: ['title'],          max: { kicker: 40, title: 70, body: 110 } },
  point:  { required: ['title'],          max: { kicker: 40, title: 60, body: 220, tip: 80, source: 100 } },
  stat:   { required: ['value', 'label', 'source'], max: { kicker: 40, value: 8, label: 60, body: 170, source: 100 } },
  list:   { required: ['title', 'items'], max: { kicker: 40, title: 60 } },
  screen: { required: ['title', 'image'], max: { kicker: 40, title: 60, note: 40 } },
  cta:    { required: [],                 max: { title: 50, body: 120, button: 26, url: 34 } },
};
const THEMES = ['cream', 'soft', 'mint', 'dark'];
const plain = s => String(s).replace(/\*\*|==|\*/g, '');

const args = process.argv.slice(2);
const flag = name => args.includes(name);
const formatArg = args.includes('--format') ? args[args.indexOf('--format') + 1] : 'both';
if (formatArg !== 'both' && !FORMATS[formatArg]) fail(`Unknown format "${formatArg}". Use tiktok, instagram or both.`);
const formats = formatArg === 'both' ? Object.keys(FORMATS) : [formatArg];
let files = args.filter(a => a.endsWith('.json')).map(a => resolve(a));
if (flag('--all')) files = readdirSync(join(here, 'carousels')).filter(f => f.endsWith('.json')).map(f => join(here, 'carousels', f));
if (!files.length) fail('Give a carousel JSON file, or --all.');

function fail(message) { console.error(message); process.exit(1); }

/** Reads a carousel, checks it, and resolves themes and image paths. */
function load(file) {
  const errors = [], warnings = [];
  const brand = JSON.parse(readFileSync(join(here, 'brand.json'), 'utf8'));
  let c;
  try { c = JSON.parse(readFileSync(file, 'utf8')); } catch (e) { return { errors: [`Not valid JSON: ${e.message}`], warnings }; }
  const slides = Array.isArray(c.slides) ? c.slides : [];
  if (slides.length < 3 || slides.length > 10) errors.push(`Needs 3 to 10 slides, has ${slides.length}.`);
  if (slides[0]?.type !== 'hook') warnings.push('The first slide is usually a "hook".');
  if (slides.at(-1)?.type !== 'cta') warnings.push('The last slide is usually a "cta".');
  if (!c.caption) warnings.push('No "caption" for the post.');

  const asset = (ref, dir, ext, where) => {
    // A bare name is one of the shared files; anything with a slash or a dot
    // is a path next to the carousel file.
    const path = /[\\/.]/.test(ref) ? resolve(dirname(file), ref) : join(here, '..', 'app-store', dir, `${ref}.${ext}`);
    if (!existsSync(path)) errors.push(`${where}: no file at ${path}`);
    return pathToFileURL(path).href;
  };
  brand.iconUrl = pathToFileURL(resolve(here, brand.icon)).href;

  const cycle = ['soft', 'cream'];
  slides.forEach((s, i) => {
    const where = `Slide ${i + 1}`, spec = TYPES[s.type];
    if (!spec) return errors.push(`${where}: unknown type "${s.type}". Use ${Object.keys(TYPES).join(', ')}.`);
    if (s.type === 'cta') Object.assign(s, { ...brand.cta, ...s });
    for (const key of spec.required) if (s[key] == null || s[key] === '') {
      errors.push(`${where} (${s.type}): missing "${key}".${key === 'source' ? ' Every number needs to say where it comes from.' : ''}`);
    }
    for (const [key, max] of Object.entries(spec.max)) if (s[key] && plain(s[key]).length > max) {
      warnings.push(`${where}: "${key}" is ${plain(s[key]).length} characters (aim for ${max} or fewer).`);
    }
    if (s.type === 'list') {
      if (!Array.isArray(s.items) || s.items.length < 2 || s.items.length > 5) errors.push(`${where}: "items" needs 2 to 5 entries.`);
      else s.items.forEach(item => { if (plain(item).length > 48) warnings.push(`${where}: list item "${plain(item)}" is long (aim for 48 characters or fewer).`); });
    }
    if (s.theme && !THEMES.includes(s.theme)) errors.push(`${where}: unknown theme "${s.theme}". Use ${THEMES.join(', ')}.`);
    s.theme ??= s.type === 'hook' ? 'cream' : s.type === 'cta' ? 'dark' : s.type === 'stat' ? 'mint' : cycle[i % 2];
    if (s.art) s.artUrl = asset(s.theme === 'dark' ? `ill-${s.art}-dark` : `ill-${s.art}`, 'art', 'svg', where);
    if (s.image) s.imageUrl = asset(s.image, 'screens', 'png', where);
    if (s.type === 'cta') s.iconUrl = brand.iconUrl;
  });
  return { carousel: { ...c, brand, slides }, errors, warnings };
}

const loaded = files.map(file => ({ file, name: basename(file, '.json'), ...load(file) }));
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

const profile = mkdtempSync(join(tmpdir(), 'carousel-chrome-'));
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

  for (const { name, carousel } of loaded) {
    const out = join(here, 'out', name);
    rmSync(out, { recursive: true, force: true });
    const n = carousel.slides.length, json = JSON.stringify(carousel);
    for (const format of formats) {
      const { w, h } = FORMATS[format];
      mkdirSync(join(out, format), { recursive: true });
      for (let i = 0; i < n; i++) {
        const [scale] = await run(`draw(${json}, "${format}", [${i}], false)`);
        if (scale < 0.8) console.warn(`${name}: note: slide ${i + 1} (${format}) has a lot of text; it was shrunk to ${Math.round(scale * 100)}%. Cut some words.`);
        await shoot(w, h, join(out, format, `${String(i + 1).padStart(2, '0')}.png`));
      }
      // Contact sheet of the whole carousel at quarter size, for a quick look.
      await run(`draw(${json}, "${format}", [${[...Array(n).keys()]}], true)`);
      await shoot(Math.ceil((n * w + (n + 1) * 40) / 4), Math.ceil((h + 80) / 4), join(out, `overview-${format}.png`));
    }
    const tags = (carousel.hashtags ?? []).map(t => `#${String(t).replace(/^#/, '')}`).join(' ');
    writeFileSync(join(out, 'caption.txt'), [carousel.caption, tags].filter(Boolean).join('\n\n') + '\n');
    console.log(`${name}: ${n} slides in ${formats.join(' and ')} at ${out}`);
  }
  ws.close();
} finally {
  chrome.kill();
  await new Promise(r => setTimeout(r, 300));
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
}
