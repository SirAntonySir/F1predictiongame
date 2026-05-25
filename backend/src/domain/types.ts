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
}

export type Constructor = {
  id: string
  name: string
  nationality: string | null
  wikipediaUrl: string | null
  imageUrl: string | null
  imageUrlOverride: string | null
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
