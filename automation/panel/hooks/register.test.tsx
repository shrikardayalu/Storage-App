import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'simpleshrink-seo',
  component: 'Pane',
  requestId: 'simpleshrink-seo',
  props: {
    title: 'SimpleShrink SEO',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

// Monday 2026-11-16, 10:00 local time.
const NOW = new Date(2026, 10, 16, 10, 0, 0).getTime()

const GUIDE = `---
title: "High Efficiency vs Most Compatible on iPhone"
topic: camera-and-formats
published: 2026-11-16
---
Body.
`
const OLD = `---
title: "How to Compress Videos on iPhone"
topic: videos
published: 2026-10-20
---
Body.
`
const DRAFT = `---
title: "Unchecked guide"
topic: videos
published: 2026-11-15
draft: true
---
Body.
`
const BACKLOG = `# Topic backlog

## Core: videos

| Status | Keyword | Angle | Tie-back |
| --- | --- | --- | --- |
| open | how to trim a video on iphone | x | y |
| open | slo-mo video storage iphone | x | y |

## Adjacent: camera and formats

| Status | Keyword | Angle | Tie-back |
| --- | --- | --- | --- |
| published | high efficiency vs most compatible iphone | x | y |
| open | proraw file size iphone | x | y |
`
const LOG = `# SEO log

## 2026-11-16 · new guide · \`high-efficiency-vs-most-compatible-iphone\`

- **Device check:** 4K at 60 fps disappears under Most Compatible.
- **Check on 2026-12-14:** indexed?
`

const files: Record<string, string> = {
  '/repo/web/content/guides/a.md': GUIDE,
  '/repo/web/content/guides/b.md': OLD,
  '/repo/web/content/guides/c.md': DRAFT,
  '/repo/automation/backlog.md': BACKLOG,
  '/repo/automation/log.md': LOG,
}

test('the panel shows pace, guides, backlog and checks from the repo files', async ($, on) => {
  on('command.register', () => ({ value: { command: 'seo-status' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.root', () => ({ value: '/repo' }))
  on('clock.now', () => ({ value: NOW }))
  on('clock.every', () => ({ value: undefined }))
  on('store.get', () => ({ value: undefined }))
  on('fs.exists', () => ({ value: true }))
  on('fs.list', () => ({
    value: ['a.md', 'b.md', 'c.md'].map(name => ({
      name,
      kind: 'file',
      size: 1,
      mtimeMs: 0,
      isLink: false,
    })),
  }))
  // The engine hands paths over in the host's own spelling (C:\repo\... on Windows).
  const plain = (path: string) => path.replace(/\\/g, '/').replace(/^[A-Za-z]:/, '')
  on('fs.read', (_, e) => ({ value: files[plain(e.path)] ?? '' }))

  await $.session.start({ cwd: '/repo', surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'seo-status', args: '' })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })

  expect(await ui.find({ type: 'Text', text: /■□□□□ {2}1 of 5 new guides/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /Room for 4 more\. Next run today at 3:20 pm\./ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /Guides \(2 live, 1 draft\)/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /draft {2}Unchecked guide/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /Backlog \(3 open\)/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /· how to trim a video on iphone/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /On your iPhone: high-efficiency.*4K at 60 fps/ })).toBeTruthy()
  // The review date is still in the future, so it isn't listed yet.
  expect(await ui.find({ type: 'Text', text: /Review results/ })).toBeFalsy()
  await ui.unmount()
})
