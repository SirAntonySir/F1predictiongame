import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as results from '../../src/repo/results.js'
import * as users from '../../src/repo/users.js'
import * as predictions from '../../src/repo/predictions.js'
import * as scoresRepo from '../../src/repo/scores.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() - 3 * 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() - 60 * 60 * 1000), status: 'scheduled'
  })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await standings.replaceDriverStandings(2026, [{ seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }])
  return { ev, ses }
}

describe('POST /admin/rescore-session/:id', () => {
  it('requires admin token', async () => {
    const { ses } = await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'POST', url: `/admin/rescore-session/${ses.id}` })
    expect(r.statusCode).toBe(401)
  })

  it('rescores a single session', async () => {
    const { ses } = await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'ad@x.com', passwordHash: 'h', displayName: 'A' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'VER' }, { position: 4, driverCode: 'VER' }, { position: 5, driverCode: 'VER' }
    ])
    await results.replaceForSession(ses.id, [
      { sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: 'Finished', points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
    ])
    const r = await app.inject({ method: 'POST', url: `/admin/rescore-session/${ses.id}`, headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json().users).toBe(1)
    expect((await scoresRepo.listForUser(u.id, 2026))[0]!.pointsTotal).toBeGreaterThan(0)
  })
})

describe('POST /admin/rescore-season/:year', () => {
  it('rescores all sessions in a season', async () => {
    const { ses } = await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'ad2@x.com', passwordHash: 'h', displayName: 'A2' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'VER' }, { position: 4, driverCode: 'VER' }, { position: 5, driverCode: 'VER' }
    ])
    await results.replaceForSession(ses.id, [
      { sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: 'Finished', points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
    ])
    const r = await app.inject({ method: 'POST', url: '/admin/rescore-season/2026', headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json().users).toBeGreaterThan(0)
  })
})
