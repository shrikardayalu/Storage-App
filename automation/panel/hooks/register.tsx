import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type {
  BacklogSection,
  Guide,
  SearchData,
  SearchRow,
  SeoStatus,
} from '../types'

const PANE = 'simpleshrink-seo'
const TITLE = 'SimpleShrink SEO'
const SITE = 'https://www.simpleshrink.com'
// Where the repo lives when the session was started somewhere else.
const HOME_REPO = 'C:/Users/shrik/OneDrive/Desktop/Storage App'
// The build refuses more than this many new guides in any 7 days
// (PUBLISHING_PACE in web/src/lib/guides.ts).
const MAX_PER_WEEK = 5
// The scheduled task "SimpleShrink SEO run": Mon, Wed, Fri, Sat at 3:20 pm.
const RUN_DAYS = [1, 3, 5, 6]
const RUN_HOUR = 15
const RUN_MINUTE = 20
const SEARCH_DAYS = 28
const SEARCH_KEY = 'search'
const DAY_MS = 24 * 60 * 60 * 1000

const status = atom({ plugin: 'simpleshrink-seo', key: 'status' } as const, null, {
  shape: 'status-1',
})

type Engine = EngineInterface

const day = (ms: number) => {
  const d = new Date(ms)
  const two = (n: number) => String(n).padStart(2, '0')

  return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`
}

const field = (front: string, name: string) => {
  const match = front.match(new RegExp(`^${name}:\\s*(.*)$`, 'm'))

  return (match?.[1] ?? '').trim().replace(/^"(.*)"$/, '$1')
}

const parseGuide = (slug: string, text: string): Guide | null => {
  const front = text.split(/^---\s*$/m)[1]
  if (front === undefined) return null

  return {
    slug,
    title: field(front, 'title'),
    published: field(front, 'published'),
    topic: field(front, 'topic'),
    isDraft: field(front, 'draft') === 'true',
  }
}

const parseBacklog = (text: string) => {
  const sections: BacklogSection[] = []
  const nextUp: string[] = []
  for (const line of text.split('\n')) {
    const heading = line.match(/^## (.+)$/)
    if (heading) {
      sections.push({ name: heading[1].trim(), open: 0, published: 0 })
      continue
    }
    const row = line.match(/^\|\s*(open|published)\s*\|\s*([^|]+)\|/)
    const section = sections[sections.length - 1]
    if (!row || !section) continue
    if (row[1] === 'published') {
      section.published += 1
      continue
    }
    section.open += 1
    if (section.open === 1) nextUp.push(row[2].trim())
  }

  return { sections: sections.filter(s => s.open + s.published > 0), nextUp }
}

const parseLog = (text: string, today: string) => {
  const entries = text.split(/^## /m).slice(1)
  const deviceChecks: string[] = []
  const reviewsDue: string[] = []
  for (const entry of entries) {
    const slug = entry.match(/`([^`]+)`/)?.[1] ?? entry.split('\n')[0]
    const check = entry.match(/\*\*Device check:\*\*\s*(.+)/)
    if (check) deviceChecks.push(`${slug}: ${check[1].trim()}`)
    const review = entry.match(/\*\*Check on (\d{4}-\d{2}-\d{2}):\*\*/)
    if (review && review[1] <= today) reviewsDue.push(`${slug} (due ${review[1]})`)
  }

  return {
    lastRun: (entries[0]?.split('\n')[0] ?? '').replace(/`/g, '').trim(),
    deviceChecks,
    reviewsDue,
  }
}

const findRepo = async ($: Engine) => {
  const root = await $.session.root().catch(() => '')
  for (const dir of [root, HOME_REPO]) {
    if (dir && (await $.fs.exists(`${dir}/automation/backlog.md`))) return dir
  }

  return ''
}

const loadSearch = async ($: Engine): Promise<SearchData | null> => {
  const stored = (await $.store.get(SEARCH_KEY).catch(() => undefined)) as
    | SearchData
    | undefined

  return stored && Array.isArray(stored.queries) ? stored : null
}

const load = async ($: Engine): Promise<SeoStatus> => {
  const now = await $.clock.now()
  const empty: SeoStatus = {
    loadedAt: now,
    problem: '',
    guides: [],
    publishedThisWeek: 0,
    backlog: [],
    nextUp: [],
    lastRun: '',
    deviceChecks: [],
    reviewsDue: [],
    search: await loadSearch($),
    searchNote: '',
    isFetchingSearch: false,
  }
  const repo = await findRepo($)
  if (!repo) {
    return { ...empty, problem: 'Could not find the SimpleShrink repo from this session.' }
  }

  const dir = `${repo}/web/content/guides`
  const files = (await $.fs.list(dir)).filter(f => f.name.endsWith('.md'))
  const parsed = await Promise.all(
    files.map(async f =>
      parseGuide(f.name.replace(/\.md$/, ''), await $.fs.read(`${dir}/${f.name}`)),
    ),
  )
  const guides = parsed
    .filter((g): g is Guide => g !== null)
    .sort((a, b) => b.published.localeCompare(a.published))
  const weekStart = day(now - 6 * DAY_MS)
  const backlog = parseBacklog(await $.fs.read(`${repo}/automation/backlog.md`))
  const log = parseLog(
    await $.fs.read(`${repo}/automation/log.md`).catch(() => ''),
    day(now),
  )

  return {
    ...empty,
    guides,
    publishedThisWeek: guides.filter(g => !g.isDraft && g.published >= weekStart).length,
    backlog: backlog.sections,
    nextUp: backlog.nextUp,
    ...log,
  }
}

const refresh = async ($: Engine) => {
  const fresh = await load($).catch(
    (error): SeoStatus => ({
      loadedAt: 0,
      problem: `Could not read the SEO files: ${String(error)}`,
      guides: [],
      publishedThisWeek: 0,
      backlog: [],
      nextUp: [],
      lastRun: '',
      deviceChecks: [],
      reviewsDue: [],
      search: null,
      searchNote: '',
      isFetchingSearch: false,
    }),
  )
  await update($, status, old => ({
    ...fresh,
    searchNote: old?.searchNote ?? '',
    isFetchingSearch: old?.isFetchingSearch ?? false,
  }))
}

type RawRow = { keys?: string[]; clicks?: number; impressions?: number; position?: number }

// gum wraps the API's answer; find its `rows` wherever they sit.
const findRows = (value: unknown, depth = 0): RawRow[] | undefined => {
  if (depth > 4 || value === null || typeof value !== 'object') return undefined
  if (Array.isArray(value)) return undefined
  const record = value as Record<string, unknown>
  if (Array.isArray(record.rows)) return record.rows as RawRow[]
  for (const inner of Object.values(record)) {
    const found = findRows(inner, depth + 1)
    if (found) return found
  }

  return undefined
}

const rows = (json: string): SearchRow[] =>
  (findRows(JSON.parse(json)) ?? []).map(r => ({
    key: r.keys?.[0] ?? '',
    clicks: r.clicks ?? 0,
    impressions: r.impressions ?? 0,
    position: r.position ?? 0,
  }))

// What gum said went wrong, in words a person can act on.
const explain = (output: string) => {
  if (/SCOPE_MISSING|no local credential|use-oauth-client/.test(output)) {
    return 'not signed in yet. Do the one-time setup in automation/README.md.'
  }
  if (/PERMISSION_DENIED/.test(output)) {
    return 'this Google account cannot read the simpleshrink.com property.'
  }
  const said = output.match(/"user_message":\s*"([^"]+)"/)?.[1]
  const last = output.trim().split('\n').slice(-1)[0]

  return said ?? (last || 'the script failed')
}

// Search Console is read by automation/gsc.sh, which runs gum inside WSL.
const fetchSearch = async ($: Engine) => {
  const note = async (searchNote: string, isFetchingSearch = false) =>
    update($, status, old => (old ? { ...old, searchNote, isFetchingSearch } : old))
  await note('Asking Search Console…', true)
  const repo = await findRepo($)
  if (!repo) return note('Could not find the repo.')

  const script = `${repo}/automation/gsc.sh`
  const ask = async (dimension: string) => {
    const ran = await $.process.run(
      ['wsl.exe', '-e', 'bash', script.replace(/^([A-Za-z]):/, (_, d: string) => `/mnt/${d.toLowerCase()}`), dimension, String(SEARCH_DAYS)],
      { timeoutMs: 90_000 },
    )
    if (ran.exitCode !== 0) {
      throw new Error(explain(`${ran.stderr}\n${ran.stdout}`))
    }

    return rows(ran.stdout)
  }

  try {
    const queries = await ask('query')
    const pages = await ask('page')
    const byImpressions = (a: SearchRow, b: SearchRow) => b.impressions - a.impressions
    const search: SearchData = {
      fetchedAt: await $.clock.now(),
      days: SEARCH_DAYS,
      clicks: pages.reduce((sum, r) => sum + r.clicks, 0),
      impressions: pages.reduce((sum, r) => sum + r.impressions, 0),
      queries: queries.sort(byImpressions).slice(0, 8),
      pages: pages.sort(byImpressions).slice(0, 8),
    }
    await $.store.set(SEARCH_KEY, search)
    await update($, status, old =>
      old ? { ...old, search, searchNote: '', isFetchingSearch: false } : old,
    )
  } catch (error) {
    await note(`Search Console: ${String(error).replace(/^Error: /, '')}`)
  }
}

const nextRun = (now: number) => {
  for (let ahead = 0; ahead < 8; ahead += 1) {
    const at = new Date(now + ahead * DAY_MS)
    at.setHours(RUN_HOUR, RUN_MINUTE, 0, 0)
    if (RUN_DAYS.includes(at.getDay()) && at.getTime() > now) {
      const name = at.toLocaleDateString('en-US', { weekday: 'long' })
      const when = ahead === 0 ? 'today' : ahead === 1 ? 'tomorrow' : name

      return `${when} at 3:20 pm`
    }
  }

  return 'Mon, Wed, Fri, Sat at 3:20 pm'
}

const ago = (now: number, then: number) => {
  const minutes = Math.max(0, Math.round((now - then) / 60_000))
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.round(minutes / 60)

  return hours < 48 ? `${hours} h ago` : `${Math.round(hours / 24)} days ago`
}

const clip = (text: string, width: number) =>
  text.length > width ? `${text.slice(0, Math.max(1, width - 1))}…` : text

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'seo-status',
      description: 'Show the SimpleShrink SEO panel: pace, next run, guides, backlog, search',
    })
    void refresh($)
    // Scheduled runs and hand edits change the files; keep the panel current.
    $.clock.every(5 * 60_000, () => void refresh($))

    return next(e)
  })

  on('command.run', { command: 'seo-status' }, async $ => {
    await refresh($)
    await $.ui.open({ id: PANE, title: TITLE })

    return { text: 'SimpleShrink SEO panel opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Link } = $.ui.resolve(e)
    const s = await read($, status)
    const width = Math.max(24, e.props.bodyColumns ?? 40)
    const now = await $.clock.now()

    if (!s) {
      return (
        <Box flexDirection="column">
          <Text dimColor>Reading the SEO files…</Text>
          <Button key="refresh" onPress={() => void refresh($)}>Refresh</Button>
        </Box>
      )
    }
    if (s.problem) {
      return (
        <Box flexDirection="column">
          <Text>{s.problem}</Text>
          <Button key="refresh" onPress={() => void refresh($)}>Try again</Button>
        </Box>
      )
    }

    const left = Math.max(0, MAX_PER_WEEK - s.publishedThisWeek)
    const drafts = s.guides.filter(g => g.isDraft)
    const live = s.guides.filter(g => !g.isDraft)
    const openTotal = s.backlog.reduce((sum, b) => sum + b.open, 0)

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="column">
          <Text bold>This week</Text>
          <Text>{`${'■'.repeat(Math.min(MAX_PER_WEEK, s.publishedThisWeek))}${'□'.repeat(left)}  ${s.publishedThisWeek} of ${MAX_PER_WEEK} new guides in the last 7 days`}</Text>
          <Text dimColor>
            {left === 0
              ? 'Week is full: runs improve existing pages.'
              : `Room for ${left} more. Next run ${nextRun(now)}.`}
          </Text>
          {s.lastRun !== '' && <Text dimColor>{clip(`Last: ${s.lastRun}`, width)}</Text>}
        </Box>

        <Box flexDirection="column">
          <Text bold>{`Guides (${live.length} live${drafts.length ? `, ${drafts.length} draft` : ''})`}</Text>
          {live.slice(0, 5).map(g => (
            <Link href={`${SITE}/guides/${g.slug}`} label={clip(`${g.published.slice(5)}  ${g.title}`, width)} />
          ))}
          {drafts.map(g => (
            <Text color="warning">{clip(`draft  ${g.title}`, width)}</Text>
          ))}
        </Box>

        {(s.deviceChecks.length > 0 || s.reviewsDue.length > 0) && (
          <Box flexDirection="column">
            <Text bold>For you to check</Text>
            {s.deviceChecks.map(c => (
              <Text>{`On your iPhone: ${c}`}</Text>
            ))}
            {s.reviewsDue.map(r => (
              <Text>{`Review results: ${r}`}</Text>
            ))}
          </Box>
        )}

        <Box flexDirection="column">
          <Text bold>{`Backlog (${openTotal} open)`}</Text>
          {s.backlog.map(b => (
            <Text dimColor>{clip(`${String(b.open).padStart(2)}  ${b.name}`, width)}</Text>
          ))}
          {s.nextUp.length > 0 && <Text>Likely next:</Text>}
          {s.nextUp.slice(0, 4).map(k => (
            <Text dimColor>{clip(`· ${k}`, width)}</Text>
          ))}
        </Box>

        <Box flexDirection="column">
          <Text bold>Search Console</Text>
          {s.search === null && s.searchNote === '' && (
            <Text dimColor>No numbers yet. Press the button to fetch them.</Text>
          )}
          {s.search !== null && (
            <Text>{`${s.search.clicks} clicks, ${s.search.impressions} impressions in ${s.search.days} days`}</Text>
          )}
          {s.search !== null && s.search.queries.length > 0 && <Text dimColor>Top searches (impressions, position):</Text>}
          {(s.search?.queries ?? []).slice(0, 6).map(q => (
            <Text dimColor>{clip(`${String(q.impressions).padStart(4)}  #${q.position.toFixed(0).padEnd(3)} ${q.key}`, width)}</Text>
          ))}
          {s.search !== null && s.search.pages.length > 0 && <Text dimColor>Top pages:</Text>}
          {(s.search?.pages ?? []).slice(0, 5).map(p => (
            <Text dimColor>{clip(`${String(p.impressions).padStart(4)}  ${p.key.replace(SITE, '') || '/'}`, width)}</Text>
          ))}
          {s.search !== null && (
            <Text dimColor>{`Fetched ${ago(now, s.search.fetchedAt)}. Google's numbers lag 2 to 3 days.`}</Text>
          )}
          {s.searchNote !== '' && <Text color={s.isFetchingSearch ? undefined : 'warning'}>{s.searchNote}</Text>}
        </Box>

        <Box flexDirection="row" gap={1}>
          <Button key="refresh" onPress={() => void refresh($)}>Refresh</Button>
          <Button key="search" onPress={() => void fetchSearch($)}>
            {s.isFetchingSearch ? 'Fetching…' : 'Fetch search numbers'}
          </Button>
        </Box>
        <Text dimColor>{`Files read ${ago(now, s.loadedAt)}. Schedule: Claude app → Scheduled.`}</Text>
      </Box>
    )
  })
}
