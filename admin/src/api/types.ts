export type CrawlStatus = {
  lastTickAt: string | null
  lastTickStatus: 'ok' | 'error' | null
  pendingCandidates: { id: number; type: string }[]
  provisionalSessions: { id: number; eventName: string; type: string }[]
}

export type AdminSessionRow = {
  id: number
  seasonYear: number
  round: number
  eventName: string
  type: string
  status: 'scheduled' | 'finished'
  scheduledStart: string
  lastReconciledAt: string | null
  resultCount: number
  provisional: boolean
}

export type SessionResultRow = {
  position: number
  driverCode: string
  driverName: string
  constructorId: string
  constructorName: string
  points: number | null
  status: string | null
  raceTime: string | null
  q1: string | null
  q2: string | null
  q3: string | null
}

export type SessionMeta = {
  id: number
  eventId: number
  type: string
  scheduledStart: string
  scheduledEnd: string
  status: 'scheduled' | 'finished'
}
