import type { SessionResultRow, DriverStanding, ConstructorStanding } from '../domain/types.js'
import type { StoredSession } from '../repo/sessions.js'
import type { StandingsEntry } from './types.js'

const DNF_STATUSES = new Set([
  'Retired', 'Accident', 'Engine', 'Collision', 'Mechanical',
  'Spun off', 'Withdrew', 'Did not start', 'Disqualified'
])

type DerivedPair = { driverCode: string | null; constructorId: string | null }

function topCount<K extends string>(counts: Map<K, number>): K | null {
  let best: K | null = null
  let bestCount = 0
  for (const [k, c] of counts) {
    if (c > bestCount) { best = k; bestCount = c }
  }
  return best
}

export function deriveMostDnfs(results: SessionResultRow[], sessions: StoredSession[]): DerivedPair {
  const eligibleSessionIds = new Set(
    sessions.filter((s) => s.type === 'race' || s.type === 'sprint').map((s) => s.id)
  )
  const driverCounts = new Map<string, number>()
  const teamCounts = new Map<string, number>()
  for (const r of results) {
    if (!eligibleSessionIds.has(r.sessionId)) continue
    if (!r.status || !DNF_STATUSES.has(r.status)) continue
    driverCounts.set(r.driverCode, (driverCounts.get(r.driverCode) ?? 0) + 1)
    teamCounts.set(r.constructorId, (teamCounts.get(r.constructorId) ?? 0) + 1)
  }
  return { driverCode: topCount(driverCounts), constructorId: topCount(teamCounts) }
}

export function derivePolesitter(results: SessionResultRow[], sessions: StoredSession[]): DerivedPair {
  const qualifyingIds = new Set(sessions.filter((s) => s.type === 'qualifying').map((s) => s.id))
  const driverCounts = new Map<string, number>()
  const teamCounts = new Map<string, number>()
  for (const r of results) {
    if (!qualifyingIds.has(r.sessionId)) continue
    if (r.position !== 1) continue
    driverCounts.set(r.driverCode, (driverCounts.get(r.driverCode) ?? 0) + 1)
    teamCounts.set(r.constructorId, (teamCounts.get(r.constructorId) ?? 0) + 1)
  }
  return { driverCode: topCount(driverCounts), constructorId: topCount(teamCounts) }
}

export function deriveMostFastestLaps(results: SessionResultRow[], sessions: StoredSession[]): DerivedPair {
  const raceIds = new Set(sessions.filter((s) => s.type === 'race').map((s) => s.id))
  const driverCounts = new Map<string, number>()
  const teamCounts = new Map<string, number>()
  for (const r of results) {
    if (!raceIds.has(r.sessionId)) continue
    if (r.fastestLap !== '1') continue
    driverCounts.set(r.driverCode, (driverCounts.get(r.driverCode) ?? 0) + 1)
    teamCounts.set(r.constructorId, (teamCounts.get(r.constructorId) ?? 0) + 1)
  }
  return { driverCode: topCount(driverCounts), constructorId: topCount(teamCounts) }
}

export function deriveWdcWcc(drivers: DriverStanding[], constructors: ConstructorStanding[]): DerivedPair {
  const wdc = drivers.find((d) => d.position === 1) ?? null
  const wcc = constructors.find((c) => c.position === 1) ?? null
  return {
    driverCode: wdc?.driverCode ?? null,
    constructorId: wcc?.constructorId ?? null
  }
}

export function deriveFinalStandings(drivers: DriverStanding[], constructors: ConstructorStanding[]): {
  drivers: StandingsEntry[]
  constructors: StandingsEntry[]
} {
  return {
    drivers: drivers
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((d) => ({ position: d.position, entityId: d.driverCode })),
    constructors: constructors
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((c) => ({ position: c.position, entityId: c.constructorId }))
  }
}
