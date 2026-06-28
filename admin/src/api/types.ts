export type CrawlStatus = {
  lastTickAt: string | null
  lastTickStatus: 'ok' | 'error' | null
  pendingCandidates: { id: number; type: string }[]
  provisionalSessions: { id: number; eventName: string; type: string }[]
}
