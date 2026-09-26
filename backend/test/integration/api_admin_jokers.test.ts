import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import { makeUser } from '../helpers/factories.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }
const HOUR = 60 * 60 * 1000

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

describe('POST /admin/sessions/:id/apply-jokers', () => {
  it('requires admin token', async () => {
    const { race2 } = await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'POST', url: `/admin/sessions/${race2.id}/apply-jokers` })
    expect(r.statusCode).toBe(401)
  })

  it('runs the joker pass for a locked race', async () => {
    const { race1, race2 } = await seed()
    const app = await buildApp({ scheduler: null })
    const u = await makeUser()
    await predictionsRepo.upsertPredictionWithPicks(u.id, race1.id, [{ position: 1, driverCode: 'VER' }])

    const r = await app.inject({ method: 'POST', url: `/admin/sessions/${race2.id}/apply-jokers`, headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json()).toEqual({ ok: true, sessionId: race2.id, applied: 1 })
  })

  it('409s when the session is not eligible (already applied)', async () => {
    const { race2 } = await seed()
    const app = await buildApp({ scheduler: null })
    await app.inject({ method: 'POST', url: `/admin/sessions/${race2.id}/apply-jokers`, headers: TOKEN })

    const again = await app.inject({ method: 'POST', url: `/admin/sessions/${race2.id}/apply-jokers`, headers: TOKEN })
    expect(again.statusCode).toBe(409)
  })
})
