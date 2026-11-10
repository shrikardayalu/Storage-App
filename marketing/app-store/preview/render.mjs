// Captures index.html frame by frame with headless Chrome (no npm packages:
// it talks to Chrome's DevTools port directly, Node 22+).
//
//   node render.mjs <frames-dir> [fps] [from-seconds] [to-seconds]
//
// render.sh runs this and then encodes the frames into the App Store video.
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] ?? join(here, 'frames'));
const fps = Number(process.argv[3] ?? 30);
const W = 1320, H = 2860, PORT = 9377;
const CHROME = process.env.CHROME ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';
mkdirSync(out, { recursive: true });

const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, '--hide-scrollbars',
  '--force-device-scale-factor=1', `--window-size=${W},${H}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'preview-chrome-'))}`, 'about:blank',
], { stdio: 'ignore' });

try {
  let page;
  for (let i = 0; i < 100 && !page; i++) {
    await new Promise(r => setTimeout(r, 200));
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      page = list.find(t => t.type === 'page');
    } catch {}
  }
  if (!page) throw new Error('Chrome did not start');

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

  await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send('Page.enable');
  const loaded = new Promise(ok => events.set('Page.loadEventFired', ok));
  await send('Page.navigate', { url: pathToFileURL(join(here, 'index.html')).href + '?render' });
  await loaded;
  await run('window.ready.then(() => true)');

  const duration = await run('DURATION');
  const from = Math.round(Number(process.argv[4] ?? 0) * fps);
  const to = Math.round(process.argv[5] ? Number(process.argv[5]) * fps : duration / 1000 * fps);
  for (let f = from; f < to; f++) {
    await run(`seek(${(f * 1000 / fps).toFixed(3)}).then(() => true)`);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(out, `f_${String(f).padStart(4, '0')}.png`), Buffer.from(shot.data, 'base64'));
    if (f % 30 === 0) console.log(`${(f / fps).toFixed(0)}s / ${(to / fps).toFixed(0)}s`);
  }
  console.log(`${to - from} frames in ${out}`);
  ws.close();
} finally {
  chrome.kill();
}
