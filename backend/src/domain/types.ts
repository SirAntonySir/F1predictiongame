export type SessionType = 'fp1' | 'fp2' | 'fp3' | 'qualifying' | 'sprint_quali' | 'sprint' | 'race'
export type SessionStatus = 'scheduled' | 'finished'

export type Season = { year: number; isCurrent: boolean }

export type Event = {
  seasonYear: number
  round: number
  name: string
  circuitName: string
  country: string
  hasSprint: boolean
}

export type Session = {
  id?: number
  eventId: number
  type: SessionType
  scheduledStart: Date
  scheduledEnd: Date
  status: SessionStatus
  openf1SessionKey: number | null
}

export type Driver = {
  code: string
  givenName: string
  familyName: string
  nationality: string | null
  permanentNumber: number | null
  wikipediaUrl: string | null
  imageUrl: string | null
  imageUrlOverride: string | null
  headshotUrl: string | null
}

export type Constructor = {
  id: string
  name: string
  nationality: string | null
  wikipediaUrl: string | null
  imageUrl: string | null
  imageUrlOverride: string | null
  teamColour: string | null
}

export type SessionResultRow = {
  sessionId: number
  position: number
  driverCode: string
  driverName: string
  constructorId: string
  constructorName: string
  raceTime: string | null
  status: string | null
  points: number | null
  fastestLap: string | null
  fastestLapTime: string | null
  fastestLapSpeed: string | null
  q1: string | null
  q2: string | null
  q3: string | null
}

export type DriverStanding = {
  seasonYear: number
  driverCode: string
  position: number
  points: number
  wins: number
  constructorId: string
}

export type ConstructorStanding = {
  seasonYear: number
  constructorId: string
  position: number
  points: number
  wins: number
}

export type User = {
  id: string
  email: string
  displayName: string
  createdAt: Date
  updatedAt: Date
}

export type UserWithSecret = User & { passwordHash: string }

export type AppSession = {
  id: string
  userId: string
  tokenHash: Buffer
  createdAt: Date
  lastUsedAt: Date
  expiresAt: Date
  userAgent: string | null
}

export type League = {
  id: string
  ownerUserId: string
  name: string
  joinCode: string
  createdAt: Date
}

export type LeagueMember = {
  leagueId: string
  userId: string
  joinedAt: Date
}

export type Prediction = {
  id: string
  userId: string
  sessionId: number
  createdAt: Date
  updatedAt: Date
}

export type PredictionPick = {
  predictionId: string
  position: number
  driverCode: string
}

export type ScoreBreakdownPerPosition = {
  position: number
  exact: boolean
  wrongPos: boolean
  points: number
}

export type ScoreBreakdown = {
  perPosition: ScoreBreakdownPerPosition[]
  teamBonus: { applied: boolean; points: number }
  rule: string
}

export type Score = {
  userId: string
  sessionId: number
  pointsTotal: number
  breakdown: ScoreBreakdown
  computedAt: Date
}

export type PreseasonCategory =
  | 'surprise' | 'disappointment' | 'dnf' | 'poles' | 'fastest_lap' | 'wdc_wcc'

export type PreseasonPick = {
  userId: string
  seasonYear: number
  category: PreseasonCategory
  driverCode: string | null
  constructorId: string | null
  updatedAt: Date
}

export type PreseasonStandingsPickRow = {
  userId: string
  seasonYear: number
  position: number
  entityId: string  // driverCode or constructorId
}

export type SubjectiveTruth = {
  seasonYear: number
  surpriseDriverCode: string | null
  surpriseConstructorId: string | null
  disappointmentDriverCode: string | null
  disappointmentConstructorId: string | null
  setAt: Date
}

export type PreseasonScoreBreakdown = {
  driver?: { picked: string | null; truth: string | null; correct: boolean; points: number }
  team?:   { picked: string | null; truth: string | null; correct: boolean; points: number }
  perPosition?: { position: number; picked: string; truth: string | null; correct: boolean; points: number }[]
  pointsTotal: number
  rule: string
}
