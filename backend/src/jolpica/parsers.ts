import type {
  Event, SessionType, SessionResultRow, DriverStanding, ConstructorStanding
} from '../domain/types.js'

type ParsedScheduleEvent = Event & {
  sessions: { type: SessionType; scheduledStart: Date; scheduledEnd: Date }[]
}

export type ParsedSchedule = {
  year: number
  events: ParsedScheduleEvent[]
}

const SESSION_DURATION_HOURS: Record<SessionType, number> = {
  fp1: 1.5, fp2: 1.5, fp3: 1, qualifying: 1, sprint_quali: 0.75, sprint: 1, race: 2
}

function parseDateTime(date: string, time: string | undefined): Date {
  return new Date(`${date}T${time ?? '00:00:00Z'}`)
}

function pushSession(
  out: { type: SessionType; scheduledStart: Date; scheduledEnd: Date }[],
  type: SessionType,
  date: string | undefined,
  time: string | undefined
): void {
  if (!date) return
  const start = parseDateTime(date, time)
  const end = new Date(start.getTime() + SESSION_DURATION_HOURS[type] * 60 * 60 * 1000)
  out.push({ type, scheduledStart: start, scheduledEnd: end })
}

export function parseSchedule(raw: unknown): ParsedSchedule {
  const data = raw as { MRData: { RaceTable: { season: string; Races: any[] } } }
  const year = Number(data.MRData.RaceTable.season)
  const events: ParsedScheduleEvent[] = data.MRData.RaceTable.Races.map((r: any) => {
    const sessions: ParsedScheduleEvent['sessions'] = []
    pushSession(sessions, 'fp1', r.FirstPractice?.date, r.FirstPractice?.time)
    pushSession(sessions, 'fp2', r.SecondPractice?.date, r.SecondPractice?.time)
    pushSession(sessions, 'fp3', r.ThirdPractice?.date, r.ThirdPractice?.time)
    pushSession(sessions, 'qualifying', r.Qualifying?.date, r.Qualifying?.time)
    pushSession(sessions, 'sprint_quali', r.SprintQualifying?.date, r.SprintQualifying?.time)
    pushSession(sessions, 'sprint', r.Sprint?.date, r.Sprint?.time)
    pushSession(sessions, 'race', r.date, r.time)
    const hasSprint = sessions.some((s) => s.type === 'sprint')
    return {
      seasonYear: year,
      round: Number(r.round),
      name: r.raceName,
      circuitName: r.Circuit.circuitName,
      country: r.Circuit.Location.country,
      hasSprint,
      sessions
    }
  })
  return { year, events }
}

function parseClassification(raw: unknown, key: 'Results' | 'QualifyingResults' | 'SprintResults'): SessionResultRow[] {
  const data = raw as { MRData: { RaceTable: { Races: any[] } } }
  const race = data.MRData.RaceTable.Races[0]
  if (!race) return []
  const arr: any[] = race[key] ?? []
  return arr.map((r) => ({
    sessionId: 0,  // filled in by caller after session is upserted
    position: Number(r.position),
    driverCode: r.Driver.code ?? String(r.Driver.driverId).toUpperCase().slice(0, 3),
    driverName: `${r.Driver.givenName} ${r.Driver.familyName}`,
    constructorId: r.Constructor.constructorId,
    constructorName: r.Constructor.name,
    raceTime: r.Time?.time ?? null,
    status: r.status ?? null,
    points: r.points != null ? Number(r.points) : null,
    fastestLap: r.FastestLap?.lap ?? null,
    fastestLapTime: r.FastestLap?.Time?.time ?? null,
    fastestLapSpeed: r.FastestLap?.AverageSpeed?.speed ?? null,
    q1: r.Q1 ?? null,
    q2: r.Q2 ?? null,
    q3: r.Q3 ?? null
  }))
}

export function parseRaceResults(raw: unknown): SessionResultRow[] {
  return parseClassification(raw, 'Results')
}

export function parseQualifyingResults(raw: unknown): SessionResultRow[] {
  return parseClassification(raw, 'QualifyingResults')
}

export function parseSprintResults(raw: unknown): SessionResultRow[] {
  return parseClassification(raw, 'SprintResults')
}

export function parseDriverStandings(raw: unknown): DriverStanding[] {
  const data = raw as { MRData: { StandingsTable: { season: string; StandingsLists: any[] } } }
  const list = data.MRData.StandingsTable.StandingsLists[0]
  if (!list) return []
  const year = Number(data.MRData.StandingsTable.season)
  return list.DriverStandings.map((s: any) => ({
    seasonYear: year,
    driverCode: s.Driver.code ?? String(s.Driver.driverId).toUpperCase().slice(0, 3),
    position: Number(s.position),
    points: Number(s.points),
    wins: Number(s.wins),
    constructorId: s.Constructors[0].constructorId
  }))
}

export function parseConstructorStandings(raw: unknown): ConstructorStanding[] {
  const data = raw as { MRData: { StandingsTable: { season: string; StandingsLists: any[] } } }
  const list = data.MRData.StandingsTable.StandingsLists[0]
  if (!list) return []
  const year = Number(data.MRData.StandingsTable.season)
  return list.ConstructorStandings.map((s: any) => ({
    seasonYear: year,
    constructorId: s.Constructor.constructorId,
    position: Number(s.position),
    points: Number(s.points),
    wins: Number(s.wins)
  }))
}

export type DriverLookup = {
  code: string
  givenName: string
  familyName: string
  nationality: string | null
  permanentNumber: number | null
  wikipediaUrl: string | null
}

export type ConstructorLookup = {
  id: string
  name: string
  nationality: string | null
  wikipediaUrl: string | null
}

function deriveCode(driver: any): string {
  return driver.code ?? String(driver.driverId).toUpperCase().slice(0, 3)
}

export function extractDriversFromResults(raw: unknown): DriverLookup[] {
  const data = raw as { MRData: { RaceTable: { Races: any[] } } }
  const race = data.MRData.RaceTable.Races[0]
  if (!race) return []
  const buckets: any[] = [
    ...(race.Results ?? []), ...(race.QualifyingResults ?? []), ...(race.SprintResults ?? [])
  ]
  const seen = new Map<string, DriverLookup>()
  for (const r of buckets) {
    const code = deriveCode(r.Driver)
    if (seen.has(code)) continue
    seen.set(code, {
      code,
      givenName: r.Driver.givenName,
      familyName: r.Driver.familyName,
      nationality: r.Driver.nationality ?? null,
      permanentNumber: r.Driver.permanentNumber ? Number(r.Driver.permanentNumber) : null,
      wikipediaUrl: r.Driver.url ?? null
    })
  }
  return [...seen.values()]
}

export function extractConstructorsFromResults(raw: unknown): ConstructorLookup[] {
  const data = raw as { MRData: { RaceTable: { Races: any[] } } }
  const race = data.MRData.RaceTable.Races[0]
  if (!race) return []
  const buckets: any[] = [
    ...(race.Results ?? []), ...(race.QualifyingResults ?? []), ...(race.SprintResults ?? [])
  ]
  const seen = new Map<string, ConstructorLookup>()
  for (const r of buckets) {
    const id = r.Constructor.constructorId
    if (seen.has(id)) continue
    seen.set(id, {
      id,
      name: r.Constructor.name,
      nationality: r.Constructor.nationality ?? null,
      wikipediaUrl: r.Constructor.url ?? null
    })
  }
  return [...seen.values()]
}
