import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as results from '../../src/repo/results.js'
import * as picks from '../../src/repo/preseasonPicks.js'
import * as preseasonStandings from '../../src/repo/preseasonStandings.js'
import * as truth from '../../src/repo/subjectiveTruth.js'
import * as scores from '../../src/repo/scores.js'
import { rescorePreseasonForSeason } from '../../src/preseason/rescorer.js'

async function seedSeason() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const code of ['VER', 'PER', 'HAM', 'RUS', 'NOR', 'PIA']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  const race = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15), scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled',
  openf1SessionKey: null
  })
  const quali = await sessions.upsertSession({
    eventId: ev.id, type: 'qualifying',
    scheduledStart: new Date(2026, 2, 7, 14), scheduledEnd: new Date(2026, 2, 7, 15), status: 'scheduled',
  openf1SessionKey: null
  })
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 400, wins: 10, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 300, wins: 4,  constructorId: 'mercedes' },
    { seasonYear: 2026, driverCode: 'NOR', position: 3, points: 250, wins: 3,  constructorId: 'mclaren' }
  ])
  await standings.replaceConstructorStandings(2026, [
    { seasonYear: 2026, constructorId: 'red_bull', position: 1, points: 700, wins: 11 },
    { seasonYear: 2026, constructorId: 'mclaren',  position: 2, points: 600, wins: 6 },
    { seasonYear: 2026, constructorId: 'mercedes', position: 3, points: 500, wins: 5 }
  ])
  return { race, quali }
}

function rr(sessionId: number, position: number, code: string, team: string, opts: Record<string, any> = {}) {
  return {
    sessionId, position, driverCode: code, driverName: code,
    constructorId: team, constructorName: team,
    raceTime: null, status: 'Finished', points: null,
    fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null,
    ...opts
  }
}

describe('rescorePreseasonForSeason', () => {
  it('scores all 7 category rows per user with at least one pick', async () => {
    const { race, quali } = await seedSeason()
    await results.replaceForSession(race.id, [
      rr(race.id, 1, 'VER', 'red_bull', { fastestLap: '1' }),
      rr(race.id, 2, 'HAM', 'mercedes'),
      rr(race.id, 20, 'PER', 'red_bull', { status: 'Retired' })
    ])
    await results.replaceForSession(quali.id, [
      rr(quali.id, 1, 'VER', 'red_bull')
    ])

    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    // Correct picks
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: 'PER', constructorId: 'red_bull' })
    await picks.upsertPick(u.id, 2026, 'poles', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.upsertPick(u.id, 2026, 'fastest_lap', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })

    const summary = await rescorePreseasonForSeason(2026)
    expect(summary.users).toBe(1)

    const list = await scores.listPreseasonForUser(u.id, 2026)
    // Expect 7 rows (6 single + 1 standings)
    expect(list).toHaveLength(7)

    const byCategory = new Map(list.map((r) => [r.category, r.pointsTotal]))
    expect(byCategory.get('dnf')).toBe(8)         // both correct
    expect(byCategory.get('poles')).toBe(8)
    expect(byCategory.get('fastest_lap')).toBe(8)
    expect(byCategory.get('wdc_wcc')).toBe(8)
    expect(byCategory.get('surprise')).toBe(0)    // truth not set
    expect(byCategory.get('disappointment')).toBe(0)
    expect(byCategory.get('standings')).toBe(0)   // no standings picks submitted
  })

  it('scores subjective categories after admin sets truth', async () => {
    await seedSeason()
    const u = await users.insertUser({ email: 's@x.com', passwordHash: 'h', displayName: 'S' })
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'HAM', constructorId: 'mclaren' })

    let summary = await rescorePreseasonForSeason(2026)
    let list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list.find((r) => r.category === 'surprise')!.pointsTotal).toBe(0)

    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'HAM', surpriseConstructorId: 'mclaren',
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    summary = await rescorePreseasonForSeason(2026)
    list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list.find((r) => r.category === 'surprise')!.pointsTotal).toBe(8)
  })

  it('scores standings picks against final ordering', async () => {
    await seedSeason()
    const u = await users.insertUser({ email: 'st@x.com', passwordHash: 'h', displayName: 'St' })
    await preseasonStandings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'VER' },   // correct
      { position: 2, entityId: 'NOR' },   // wrong (truth: HAM)
      { position: 3, entityId: 'HAM' }    // wrong (truth: NOR)
    ])
    await preseasonStandings.replaceConstructorPicks(u.id, 2026, [
      { position: 1, entityId: 'red_bull' }   // correct
    ])
    await rescorePreseasonForSeason(2026)
    const list = await scores.listPreseasonForUser(u.id, 2026)
    const standings = list.find((r) => r.category === 'standings')!
    expect(standings.pointsTotal).toBe(3 + 4)  // 1 driver correct + 1 team correct
  })

  it('is idempotent', async () => {
    await seedSeason()
    const u = await users.insertUser({ email: 'i@x.com', passwordHash: 'h', displayName: 'I' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    await rescorePreseasonForSeason(2026)
    await rescorePreseasonForSeason(2026)
    const list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list).toHaveLength(7)
    expect(list.find((r) => r.category === 'wdc_wcc')!.pointsTotal).toBe(8)
  })

  it('no-op when season has no events', async () => {
    await seasons.upsertSeason({ year: 2099, isCurrent: false })
    const summary = await rescorePreseasonForSeason(2099)
    expect(summary).toEqual({ users: 0, totalPoints: 0 })
  })
})
