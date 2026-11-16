export type Guide = {
  slug: string
  title: string
  published: string
  topic: string
  isDraft: boolean
}

export type BacklogSection = { name: string; open: number; published: number }

export type SearchRow = {
  key: string
  clicks: number
  impressions: number
  position: number
}

export type SearchData = {
  fetchedAt: number
  days: number
  clicks: number
  impressions: number
  queries: SearchRow[]
  pages: SearchRow[]
}

export type SeoStatus = {
  loadedAt: number
  /** Why nothing could be read, when it couldn't. */
  problem: string
  guides: Guide[]
  publishedThisWeek: number
  backlog: BacklogSection[]
  nextUp: string[]
  lastRun: string
  deviceChecks: string[]
  reviewsDue: string[]
  search: SearchData | null
  /** What happened the last time Search Console was asked. */
  searchNote: string
  isFetchingSearch: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'simpleshrink-seo': { status: Shaped<SeoStatus | null> }
  }
}
