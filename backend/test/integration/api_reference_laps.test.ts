import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'
import * as bestLaps from '../../src/repo/bestLaps.js'

/// Build a race weekend with finished FP2/FP3/Q sessions and a future race
/// session. Seeds session_result with q1/q2/q3 lap-time strings for the quali,
/// and best-laps for each FP. Returns the race session id (the "predict" target).
async function seedRaceWeekend() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
  })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({
      id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
    })
  }
  for (const code of ['VER', 'HAM', 'NOR']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
  const t0 = new Date('2026-03-15T10:00:00Z').getTime()
  const fp2 = await sessions.upsertSession({
    eventId: ev.id, type: 'fp2',
    scheduledStart: new Date(t0), scheduledEnd: new Date(t0 + 60 * 60 * 1000),
    status: 'finished', openf1SessionKey: null
  })
  const fp3 = await sessions.upsertSession({
    eventId: ev.id, type: 'fp3',
    scheduledStart: new Date(t0 + 2 * 3600 * 1000), scheduledEnd: new Date(t0 + 3 * 3600 * 1000),
    status: 'finished', openf1SessionKey: null
  })
  const quali = await sessions.upsertSession({
    eventId: ev.id, type: 'qualifying',
    scheduledStart: new Date(t0 + 4 * 3600 * 1000), scheduledEnd: new Date(t0 + 5 * 3600 * 1000),
    status: 'finished', openf1SessionKey: null
  })
  const race = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(t0 + 24 * 3600 * 1000), scheduledEnd: new Date(t0 + 26 * 3600 * 1000),
    status: 'scheduled', openf1SessionKey: null
  })

  // Quali results: VER ran all three, NOR knocked out in Q2 (so q3 is null),
  // HAM knocked out in Q1 (q2/q3 null).
  await results.replaceForSession(quali.id!, [
    {
      sessionId: quali.id!, position: 1, driverCode: 'VER', driverName: 'Max',
      constructorId: 'red_bull', constructorName: 'Red Bull',
      raceTime: null, status: null, points: null,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: '1:30.500', q2: '1:30.000', q3: '1:29.800'
    },
    {
      sessionId: quali.id!, position: 2, driverCode: 'NOR', driverName: 'Lando',
      constructorId: 'mclaren', constructorName: 'McLaren',
      raceTime: null, status: null, points: null,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: '1:30.700', q2: '1:30.200', q3: null
    },
    {
      sessionId: quali.id!, position: 3, driverCode: 'HAM', driverName: 'Lewis',
      constructorId: 'mercedes', constructorName: 'Mercedes',
      raceTime: null, status: null, points: null,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: '1:31.100', q2: null, q3: null
    }
  ])

  // FP best laps — would otherwise be the reference set.
  await bestLaps.replaceForSession(fp2.id!, [
    { driverCode: 'VER', lapMs: 92000, s1Ms: 31000, s2Ms: 30000, s3Ms: 31000, lapNumber: 5 }
  ])
  await bestLaps.replaceForSession(fp3.id!, [
    { driverCode: 'VER', lapMs: 91500, s1Ms: null, s2Ms: null, s3Ms: null, lapNumber: 7 }
  ])

  return { raceId: race.id!, qualiId: quali.id!, fp2Id: fp2.id!, fp3Id: fp3.id! }
}

/// Build a SPRINT weekend: FP1, Sprint Quali (Fri), Sprint (Sat AM),
/// Qualifying (Sat PM) all finished, plus a future race. Both SQ and Q carry
/// q1/q2/q3 lap strings so we can tell which one the race references.
async function seedSprintWeekend() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 2, name: 'Silverstone', circuitName: 'SIL', country: 'GB', hasSprint: true
  })
  for (const c of ['red_bull', 'mclaren']) {
    await constructors.upsertConstructor({
      id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
    })
  }
  for (const code of ['VER', 'NOR']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
  const t0 = new Date('2026-07-03T10:00:00Z').getTime()
  const h = 3600 * 1000
  const mk = (type: string, offH: number, status: string) => sessions.upsertSession({
    eventId: ev.id, type: type as never,
    scheduledStart: new Date(t0 + offH * h), scheduledEnd: new Date(t0 + offH * h + h),
    status: status as never, openf1SessionKey: null
  })
  await mk('fp1', 0, 'finished')
  const sq = await mk('sprint_quali', 5, 'finished') // Fri
  const sprint = await mk('sprint', 25, 'finished') // Sat AM
  const quali = await mk('qualifying', 29, 'finished') // Sat PM
  const race = await mk('race', 52, 'scheduled') // Sun

  // Distinct lap strings so we can tell SQ from Q in the response.
  await results.replaceForSession(sq.id!, [
    {
      sessionId: sq.id!, position: 1, driverCode: 'VER', driverName: 'Max',
      constructorId: 'red_bull', constructorName: 'Red Bull',
      raceTime: null, status: null, points: null,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: '1:29.900', q2: '1:29.500', q3: '1:29.100'
    }
  ])
  await results.replaceForSession(quali.id!, [
    {
      sessionId: quali.id!, position: 1, driverCode: 'VER', driverName: 'Max',
      constructorId: 'red_bull', constructorName: 'Red Bull',
      raceTime: null, status: null, points: null,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: '1:28.900', q2: '1:28.500', q3: '1:28.100'
    }
  ])
  // Sprint race best lap — the reference when predicting Qualifying.
  await bestLaps.replaceForSession(sprint.id!, [
    { driverCode: 'VER', lapMs: 90800, s1Ms: 30000, s2Ms: 30300, s3Ms: 30500, lapNumber: 12 }
  ])
  return { raceId: race.id!, qualiId: quali.id!, sqId: sq.id!, sprintId: sprint.id! }
}

describe('GET /api/sessions/:id/reference-laps — sprint weekend', () => {
  it('references the Saturday Qualifying, not the Friday Sprint Quali, when predicting the race', async () => {
    const { raceId } = await seedSprintWeekend()
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${raceId}/reference-laps` })
    expect(res.statusCode).toBe(200)
    const body = res.json() as {
      references: { label: string; type: string; laps: { driverCode: string; lapMs: number }[] }[]
    }
    // The most recent knockout is Q (Sat), not SQ (Fri) — labels + times prove it.
    expect(body.references.map((r) => r.label)).toEqual(['Q1', 'Q2', 'Q3'])
    expect(body.references.every((r) => r.type === 'qualifying')).toBe(true)
    // Q1 lap is the qualifying's 1:28.900 (88900 ms), not SQ's 1:29.900.
    expect(body.references[0]!.laps.find((l) => l.driverCode === 'VER')!.lapMs).toBe(88900)
  })

  it('references the Saturday Sprint, not the Friday Sprint Quali, when predicting qualifying', async () => {
    const { qualiId } = await seedSprintWeekend()
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${qualiId}/reference-laps` })
    expect(res.statusCode).toBe(200)
    const body = res.json() as {
      references: { label: string; type: string; laps: { driverCode: string; lapMs: number }[] }[]
    }
    // Most recent finished session before Qualifying is the Sprint (a race, not
    // a knockout) → no SQ expansion. Sprint is the last (most recent) column.
    expect(body.references.map((r) => r.label)).toEqual(['FP1', 'SQ', 'SPR'])
    expect(body.references.map((r) => r.label)).not.toContain('SQ1')
    const spr = body.references.find((r) => r.label === 'SPR')!
    expect(spr.laps.find((l) => l.driverCode === 'VER')!.lapMs).toBe(90800)
  })
})

describe('GET /api/sessions/:id/reference-laps — qualifying expansion', () => {
  it('expands qualifying into Q1/Q2/Q3 entries and drops FP references when predicting race', async () => {
    const { raceId } = await seedRaceWeekend()
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${raceId}/reference-laps` })
    expect(res.statusCode).toBe(200)
    const body = res.json() as {
      references: { label: string; type: string; laps: { driverCode: string; lapMs: number }[] }[]
    }
    expect(body.references.map((r) => r.label)).toEqual(['Q1', 'Q2', 'Q3'])

    // Each segment carries the per-driver lap from that knockout only.
    const q1 = body.references[0]!
    const q2 = body.references[1]!
    const q3 = body.references[2]!
    expect(q1.laps.find((l) => l.driverCode === 'VER')!.lapMs).toBe(90500)
    expect(q1.laps.find((l) => l.driverCode === 'NOR')!.lapMs).toBe(90700)
    expect(q1.laps.find((l) => l.driverCode === 'HAM')!.lapMs).toBe(91100)

    expect(q2.laps.find((l) => l.driverCode === 'VER')!.lapMs).toBe(90000)
    expect(q2.laps.find((l) => l.driverCode === 'NOR')!.lapMs).toBe(90200)
    expect(q2.laps.find((l) => l.driverCode === 'HAM')).toBeUndefined()

    expect(q3.laps.find((l) => l.driverCode === 'VER')!.lapMs).toBe(89800)
    expect(q3.laps.find((l) => l.driverCode === 'NOR')).toBeUndefined()
    expect(q3.laps.find((l) => l.driverCode === 'HAM')).toBeUndefined()
  })

  it('reports the type of each Q segment as qualifying so the frontend keeps team-color mapping', async () => {
    const { raceId } = await seedRaceWeekend()
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${raceId}/reference-laps` })
    const body = res.json() as { references: { type: string }[] }
    expect(body.references.every((r) => r.type === 'qualifying')).toBe(true)
  })

  it('falls back to FP best-laps when predicting qualifying (no quali yet)', async () => {
    const { qualiId } = await seedRaceWeekend()
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${qualiId}/reference-laps` })
    expect(res.statusCode).toBe(200)
    const body = res.json() as { references: { label: string }[] }
    expect(body.references.map((r) => r.label)).toEqual(['FP2', 'FP3'])
  })
})

describe('GET /api/sessions/:id/reference-laps — sector tiers from knockout-tagged rows', () => {
  it('returns sector tiers per Q-segment when knockout rows are seeded', async () => {
    const { raceId, qualiId } = await seedRaceWeekend()
    // VER fastest s1 in Q3 (sessionBest within Q3); NOR fastest s2 in Q2.
    await bestLaps.replaceForSession(qualiId, [
      { driverCode: 'VER', knockout: 1, lapMs: 90500, s1Ms: 30000, s2Ms: 30000, s3Ms: 30500, lapNumber: 3 },
      { driverCode: 'VER', knockout: 2, lapMs: 90000, s1Ms: 29800, s2Ms: 30000, s3Ms: 30200, lapNumber: 8 },
      { driverCode: 'VER', knockout: 3, lapMs: 89800, s1Ms: 29700, s2Ms: 29800, s3Ms: 30300, lapNumber: 14 },
      { driverCode: 'NOR', knockout: 1, lapMs: 90700, s1Ms: 30200, s2Ms: 30200, s3Ms: 30300, lapNumber: 4 },
      { driverCode: 'NOR', knockout: 2, lapMs: 90200, s1Ms: 30000, s2Ms: 29900, s3Ms: 30300, lapNumber: 9 }
    ])
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${raceId}/reference-laps` })
    const body = res.json() as {
      references: { label: string; laps: { driverCode: string; s1Tier: string; s2Tier: string; lapNumber: number | null }[] }[]
    }
    expect(body.references.map((r) => r.label)).toEqual(['Q1', 'Q2', 'Q3'])
    const verQ3 = body.references[2]!.laps.find((l) => l.driverCode === 'VER')!
    expect(verQ3.s1Tier).toBe('sessionBest')
    expect(verQ3.lapNumber).toBe(14)
    const norQ2 = body.references[1]!.laps.find((l) => l.driverCode === 'NOR')!
    expect(norQ2.s2Tier).toBe('sessionBest')
  })
})
