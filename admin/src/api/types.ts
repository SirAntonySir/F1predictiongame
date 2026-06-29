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

export type Season = {
  year: number
  isCurrent: boolean
}

export type AdminLeague = {
  id: string
  name: string
  ownerUserId: string
  ownerDisplayName: string
  memberCount: number
  joinCode: string
  hasPassword: boolean
  createdAt: string
}

export type AdminLeagueMember = {
  userId: string
  displayName: string
  email: string
  role: 'owner' | 'member'
  joinedAt: string
}

export type AdminLeagueDetail = {
  league: AdminLeague
  members: AdminLeagueMember[]
}

export type AdminUserRow = {
  id: string
  email: string
  displayName: string
  createdAt: string
  leagueCount: number
}

export type AdminPrediction = {
  predictionId: string
  userId: string
  displayName: string
  sessionId: number
  source: string
  updatedAt: string
  picks: { position: number; driverCode: string }[]
}

export type AdminDriver = {
  code: string
  givenName: string
  familyName: string
  nationality: string | null
  permanentNumber: number | null
  wikipediaUrl: string | null
  imageUrl: string | null
  imageUrlOverride: string | null
  headshotUrl: string | null
  image: string | null
}

export type AdminConstructor = {
  id: string
  name: string
  nationality: string | null
  wikipediaUrl: string | null
  imageUrl: string | null
  imageUrlOverride: string | null
  teamColour: string | null
  image: string | null
}

export type SessionMeta = {
  id: number
  eventId: number
  type: string
  scheduledStart: string
  scheduledEnd: string
  status: 'scheduled' | 'finished'
}
