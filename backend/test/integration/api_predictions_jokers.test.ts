import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import { applyJokersForSession } from '../../src/jokers/applier.js'

const HOUR = 60 * 60 * 1000

const auth = (token: string) => ({ authorization: `Bearer ${token}` })

/// Two race weekends: round 1 locked a week ago, round 2 locked an hour ago.
async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await drivers.upsertDriver({
    code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  const ev1 = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  const ev2 = await events.upsertEvent({ seasonYear: 2026, round: 2, name: 'J', circuitName: 'C', country: 'X', hasSprint: false })
  const race1 = await sessions.upsertSession({
    eventId: ev1.id, type: 'race',
    scheduledStart: new Date(Date.now() - 7 * 24 * HOUR),
    scheduledEnd: new Date(Date.now() - 7 * 24 * HOUR + 2 * HOUR),
    status: 'scheduled', openf1SessionKey: null
  })
  const race2 = await sessions.upsertSession({
    eventId: ev2.id, type: 'race',
    scheduledStart: new Date(Date.now() - 1 * HOUR),
    scheduledEnd: new Date(Date.now() + 1 * HOUR),
    status: 'scheduled', openf1SessionKey: null
  })
  return { race1, race2 }
}

async function buildAndUser() {
  const app = await buildApp({ scheduler: null })
  const r = await app.inject({
    method: 'POST', url: '/api/auth/signup',
    payload: { email: `joker-${Date.now()}@x.com`, password: 'hunter22', displayName: 'J' }
  })
  return { app, token: r.json().token as string, userId: r.json().user.id as string }
}

describe('joker fields in the predictions API', () => {
  it('reports 3 jokers remaining for a fresh user', async () => {
    await seed()
    const { app, token } = await buildAndUser()

    const r = await app.inject({ method: 'GET', url: '/api/predictions/upcoming', headers: auth(token) })
    expect(r.statusCode).toBe(200)
    expect(r.json().jokersRemaining).toBe(3)
    for (const entry of r.json().upcoming) expect(entry.isJoker).toBe(false)
  })

  it('counts a spent joker and flags the filled session', async () => {
    const { race1, race2 } = await seed()
    const { app, token, userId } = await buildAndUser()
    await predictionsRepo.upsertPredictionWithPicks(userId, race1.id, [{ position: 1, driverCode: 'VER' }])
    await applyJokersForSession(race2.id)

    const r = await app.inject({ method: 'GET', url: '/api/predictions/upcoming', headers: auth(token) })
    expect(r.json().jokersRemaining).toBe(2)
    const byId = new Map(r.json().upcoming.map((e: any) => [e.session.id, e]))
    expect((byId.get(race1.id) as any).isJoker).toBe(false)
    expect((byId.get(race2.id) as any).isJoker).toBe(true)
    expect((byId.get(race2.id) as any).myPicks).toEqual([{ position: 1, driverCode: 'VER' }])

    const mine = await app.inject({ method: 'GET', url: `/api/sessions/${race2.id}/my-prediction`, headers: auth(token) })
    expect(mine.json().prediction.isJoker).toBe(true)
  })

  it('flags joker predictions in the post-lock everyone view', async () => {
    const { race1, race2 } = await seed()
    const { app, token, userId } = await buildAndUser()
    await predictionsRepo.upsertPredictionWithPicks(userId, race1.id, [{ position: 1, driverCode: 'VER' }])
    await applyJokersForSession(race2.id)

    const r = await app.inject({ method: 'GET', url: `/api/sessions/${race2.id}/predictions`, headers: auth(token) })
    expect(r.statusCode).toBe(200)
    const mine = r.json().predictions.find((p: any) => p.userId === userId)
    expect(mine.isJoker).toBe(true)
  })
})
