import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import { applyJokersForSession, runJokersTick } from '../../src/jokers/applier.js'
import { makeUser } from '../helpers/factories.js'

const NOW = new Date('2026-06-10T15:00:00.000Z')
const HOUR = 60 * 60 * 1000

const racePicks = [
  { position: 1, driverCode: 'VER' },
  { position: 2, driverCode: 'HAM' },
  { position: 3, driverCode: 'NOR' },
  { position: 4, driverCode: 'PIA' },
  { position: 5, driverCode: 'RUS' }
]

const otherPicks = [
  { position: 1, driverCode: 'RUS' },
  { position: 2, driverCode: 'PIA' },
  { position: 3, driverCode: 'NOR' },
  { position: 4, driverCode: 'HAM' },
  { position: 5, driverCode: 'VER' }
]

async function seedSeason() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const code of ['VER', 'HAM', 'NOR', 'PIA', 'RUS']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
}

/// One race weekend: event at [round] whose race starts [startOffsetHours]
/// relative to NOW. Negative = already locked. Stays status='scheduled' —
/// the joker pass keys off lock (scheduledStart), not results.
async function makeRace(round: number, startOffsetHours: number, type: 'race' | 'qualifying' = 'race') {
  const ev = await events.upsertEvent({
    seasonYear: 2026, round, name: `GP ${round}`, circuitName: `C${round}`, country: 'XX', hasSprint: false
  })
  const start = new Date(NOW.getTime() + startOffsetHours * HOUR)
  return sessions.upsertSession({
    eventId: ev.id, type,
    scheduledStart: start,
    scheduledEnd: new Date(start.getTime() + 2 * HOUR),
    status: 'scheduled', openf1SessionKey: null
  })
}

async function adminRows(sessionId: number) {
  return predictionsRepo.listForAdmin({ sessionId })
}

describe('applyJokersForSession', () => {
  it('copies the previous race picks as a joker prediction and stamps the session', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    const summary = await applyJokersForSession(race2.id, NOW)
    expect(summary).toEqual({ sessionId: race2.id, applied: 1 })

    const rows = await adminRows(race2.id)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.userId).toBe(u.id)
    expect(rows[0]!.source).toBe('joker')
    expect(rows[0]!.picks).toEqual(racePicks)

    const stamped = await sessions.getById(race2.id)
    expect(stamped!.jokersAppliedAt).toBeInstanceOf(Date)
  })

  it('leaves users who already have a prediction for the session untouched', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)
    await predictionsRepo.upsertPredictionWithPicks(u.id, race2.id, otherPicks)

    const summary = await applyJokersForSession(race2.id, NOW)
    expect(summary).toEqual({ sessionId: race2.id, applied: 0 })

    const rows = await adminRows(race2.id)
    expect(rows).toHaveLength(1)
    expect(rows[0]!.source).toBe('app')
    expect(rows[0]!.picks).toEqual(otherPicks)
  })

  it('spends no joker when the previous race prediction has no picks', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, -1)
    const u = await makeUser()
    // Locked in with zero slots filled — nothing worth copying.
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, [])

    const summary = await applyJokersForSession(race2.id, NOW)
    expect(summary).toEqual({ sessionId: race2.id, applied: 0 })
    expect(await adminRows(race2.id)).toHaveLength(0)
  })

  it('spends no joker for a user without a previous race prediction', async () => {
    await seedSeason()
    await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, -1)
    await makeUser()

    const summary = await applyJokersForSession(race2.id, NOW)
    expect(summary).toEqual({ sessionId: race2.id, applied: 0 })
    expect(await adminRows(race2.id)).toHaveLength(0)
  })

  it('ignores non-race picks from the previous weekend', async () => {
    await seedSeason()
    const quali1 = await makeRace(1, -7 * 24, 'qualifying')
    const race2 = await makeRace(2, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, quali1.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' }
    ])

    const summary = await applyJokersForSession(race2.id, NOW)
    expect(summary).toEqual({ sessionId: race2.id, applied: 0 })
    expect(await adminRows(race2.id)).toHaveLength(0)
  })

  it('chains: a joker-filled previous race still feeds the next joker', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -14 * 24)
    const race2 = await makeRace(2, -7 * 24)
    const race3 = await makeRace(3, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    await applyJokersForSession(race2.id, new Date(NOW.getTime() - 7 * 24 * HOUR))
    const summary = await applyJokersForSession(race3.id, NOW)
    expect(summary).toEqual({ sessionId: race3.id, applied: 1 })

    const rows = await adminRows(race3.id)
    expect(rows[0]!.source).toBe('joker')
    expect(rows[0]!.picks).toEqual(racePicks)
  })

  it('stops after 3 jokers in a season', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -28 * 24)
    const race2 = await makeRace(2, -21 * 24)
    const race3 = await makeRace(3, -14 * 24)
    const race4 = await makeRace(4, -7 * 24)
    const race5 = await makeRace(5, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    // Three missed races in a row burn all three jokers…
    for (const [i, r] of [race2, race3, race4].entries()) {
      const at = new Date(NOW.getTime() - (21 - 7 * i) * 24 * HOUR)
      expect((await applyJokersForSession(r.id, at))!.applied).toBe(1)
    }
    // …so the fourth miss scores nothing.
    const summary = await applyJokersForSession(race5.id, NOW)
    expect(summary).toEqual({ sessionId: race5.id, applied: 0 })
    expect(await adminRows(race5.id)).toHaveLength(0)
  })

  it('is a no-op when jokers were already applied for the session', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    expect((await applyJokersForSession(race2.id, NOW))!.applied).toBe(1)
    expect(await applyJokersForSession(race2.id, NOW)).toBeNull()
    expect(await adminRows(race2.id)).toHaveLength(1)
  })

  it('refuses sessions that have not locked yet', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, +5)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    expect(await applyJokersForSession(race2.id, NOW)).toBeNull()
    expect(await adminRows(race2.id)).toHaveLength(0)
    expect((await sessions.getById(race2.id))!.jokersAppliedAt).toBeNull()
  })

  it('refuses non-race sessions', async () => {
    await seedSeason()
    const quali = await makeRace(1, -1, 'qualifying')
    expect(await applyJokersForSession(quali.id, NOW)).toBeNull()
  })

  it('stamps the season opener without spending anything', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -1)
    const u = await makeUser()
    void u

    const summary = await applyJokersForSession(race1.id, NOW)
    expect(summary).toEqual({ sessionId: race1.id, applied: 0 })
    expect((await sessions.getById(race1.id))!.jokersAppliedAt).toBeInstanceOf(Date)
  })
})

describe('runJokersTick', () => {
  it('applies jokers for a freshly locked race, then goes quiet', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    const race2 = await makeRace(2, -1)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    const first = await runJokersTick(NOW)
    expect(first).toEqual({ sessions: 1, applied: 1 })
    expect((await adminRows(race2.id))[0]!.source).toBe('joker')

    expect(await runJokersTick(NOW)).toEqual({ sessions: 0, applied: 0 })
  })

  it('ignores races that locked outside the catch-up window', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -14 * 24)
    const race2 = await makeRace(2, -50)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    expect(await runJokersTick(NOW)).toEqual({ sessions: 0, applied: 0 })
    expect(await adminRows(race2.id)).toHaveLength(0)
    expect((await sessions.getById(race2.id))!.jokersAppliedAt).toBeNull()
  })

  it('ignores races that have not locked yet', async () => {
    await seedSeason()
    const race1 = await makeRace(1, -7 * 24)
    await makeRace(2, +5)
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, racePicks)

    expect(await runJokersTick(NOW)).toEqual({ sessions: 0, applied: 0 })
  })
})
