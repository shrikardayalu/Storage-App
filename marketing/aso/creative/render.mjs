// Renders the App Store product page header and search results asset.
// No npm packages: drives headless Chrome over its DevTools port, like
// ../screenshots/render.mjs. Needs an internet connection for the fonts.
//
//   node marketing/aso/creative/render.mjs            header.png and search.png
//   node marketing/aso/creative/render.mjs --guides   also *-guides.png with Apple's safe areas drawn on
//
// Output: out/header.png (3840 x 1646) and out/search.png (3840 x 2560),
// opaque PNGs, the sizes App Store Connect lists for each slot.
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const PORT = 9381;
const ASSETS = { header: [3840, 1646], search: [3840, 2560] };
const guides = process.argv.includes('--guides');

const CHROME = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome', '/usr/bin/chromium',
].find(p => p && existsSync(p));
if (!CHROME) { console.error('Could not find Chrome or Edge. Set CHROME to the browser path.'); process.exit(1); }

const profile = mkdtempSync(join(tmpdir(), 'aso-creative-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, '--hide-scrollbars', '--allow-file-access-from-files',
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
  await send('Page.enable');

  const out = join(here, 'out');
  mkdirSync(out, { recursive: true });
  const jobs = Object.keys(ASSETS).flatMap(name => guides ? [[name, false], [name, true]] : [[name, false]]);
  for (const [name, withGuides] of jobs) {
    const [w, h] = ASSETS[name];
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    const loaded = new Promise(ok => events.set('Page.loadEventFired', ok));
    const url = `${pathToFileURL(join(here, 'template.html')).href}?asset=${name}${withGuides ? '&guides=1' : ''}`;
    await send('Page.navigate', { url });
    await loaded;
    const r = await send('Runtime.evaluate', { expression: 'window.ready', awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
    const size = r.result.value;
    if (size.w !== w || size.h !== h) throw new Error(`${name} drew at ${size.w}x${size.h}, expected ${w}x${h}.`);
    const { data } = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: w, height: h, scale: 1 } });
    const file = join(out, `${name}${withGuides ? '-guides' : ''}.png`);
    writeFileSync(file, Buffer.from(data, 'base64'));
    console.log(`${file} (${w}x${h})`);
  }
  ws.close();
} finally {
  chrome.kill();
  await new Promise(r => setTimeout(r, 300));
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
}
