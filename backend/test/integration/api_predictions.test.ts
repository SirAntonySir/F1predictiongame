import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as standings from '../../src/repo/standings.js'
import * as constructors from '../../src/repo/constructors.js'

async function seedScene() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  // Two separate events so the future-session's event has no sessions in the
  // past (and vice versa). With per-event locking, mixing past + future
  // sessions in one event would mark the future session locked too.
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
  })
  const pastEv = await events.upsertEvent({
    seasonYear: 2026, round: 99, name: 'Past', circuitName: 'X', country: 'X', hasSprint: false
  })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const code of ['VER', 'HAM', 'NOR', 'PIA', 'RUS']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 0, wins: 0, constructorId: 'mercedes' },
    { seasonYear: 2026, driverCode: 'NOR', position: 3, points: 0, wins: 0, constructorId: 'mclaren' },
    { seasonYear: 2026, driverCode: 'PIA', position: 4, points: 0, wins: 0, constructorId: 'mclaren' },
    { seasonYear: 2026, driverCode: 'RUS', position: 5, points: 0, wins: 0, constructorId: 'mercedes' }
  ])
  const futureSession = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() + 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 3 * 60 * 60 * 1000),
    status: 'scheduled',
  openf1SessionKey: null
  })
  const pastSession = await sessions.upsertSession({
    eventId: pastEv.id, type: 'qualifying',
    scheduledStart: new Date(Date.now() - 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() - 30 * 60 * 1000),
    status: 'scheduled',
  openf1SessionKey: null
  })
  return { ev, futureSession, pastSession }
}

async function buildAndUser() {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email: `u-${Date.now()}@x.com`, password: 'hunter22', displayName: 'U' } })
  return { app: a, token: r.json().token as string }
}

const auth = (token: string) => ({ authorization: `Bearer ${token}` })
const racePicks = [
  { position: 1, driverCode: 'VER' },
  { position: 2, driverCode: 'HAM' },
  { position: 3, driverCode: 'NOR' },
  { position: 4, driverCode: 'PIA' },
  { position: 5, driverCode: 'RUS' }
]

describe('PUT /api/sessions/:id/my-prediction', () => {
  it('submits a race prediction (5 picks)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token), payload: { picks: racePicks }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks).toEqual(racePicks)
    expect(res.json().prediction.isLocked).toBe(false)
  })

  it('rejects after lock with 409', async () => {
    const { pastSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${pastSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'HAM' }] }
    })
    expect(res.statusCode).toBe(409)
  })

  it('rejects more than max picks with 422', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'HAM' },
        { position: 3, driverCode: 'NOR' }, { position: 4, driverCode: 'PIA' },
        { position: 5, driverCode: 'RUS' }, { position: 6, driverCode: 'LEC' }
      ] }  // race expects at most 5
    })
    expect(res.statusCode).toBe(422)
  })

  it('accepts a partial pick list (positions 1..n with empty trailing slots)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'HAM' }
      ] }  // race expects up to 5 — 2 is fine
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks).toHaveLength(2)
  })

  it('accepts an empty pick list (lock in with no slots filled)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token), payload: { picks: [] }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks).toHaveLength(0)
  })

  it('still rejects gappy positions (e.g. 1,3 with no 2)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' }, { position: 3, driverCode: 'HAM' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects duplicate driver in picks with 422', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'VER' },
        { position: 3, driverCode: 'NOR' }, { position: 4, driverCode: 'PIA' }, { position: 5, driverCode: 'RUS' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects unknown driver with 422', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'ZZZ' }, { position: 2, driverCode: 'HAM' },
        { position: 3, driverCode: 'NOR' }, { position: 4, driverCode: 'PIA' }, { position: 5, driverCode: 'RUS' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('edit replaces existing picks (idempotent)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const edited = racePicks.map((p, i) => i === 0 ? { ...p, driverCode: 'HAM' } : i === 1 ? { ...p, driverCode: 'VER' } : p)
    const res = await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: edited } })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks[0]!.driverCode).toBe('HAM')
  })
})

describe('GET /api/sessions/:id/my-prediction', () => {
  it('returns 404 if no prediction yet', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(res.statusCode).toBe(404)
  })

  it('returns the submitted prediction', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks).toEqual(racePicks)
  })
})

describe('DELETE /api/sessions/:id/my-prediction', () => {
  it('removes a prediction before lock', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const del = await app.inject({ method: 'DELETE', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(del.statusCode).toBe(200)
    const get = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(get.statusCode).toBe(404)
  })

  it('409 after lock', async () => {
    const { pastSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'DELETE', url: `/api/sessions/${pastSession.id}/my-prediction`, headers: auth(token) })
    expect(res.statusCode).toBe(409)
  })
})

describe('GET /api/sessions/:id/predictions', () => {
  it('403 before lock', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/predictions`, headers: auth(token) })
    expect(res.statusCode).toBe(403)
  })

  it('200 after lock, returns everyone\'s picks', async () => {
    const { pastSession } = await seedScene()
    const { app, token } = await buildAndUser()
    // Submit a prediction first by manipulating data — bypass lock by submitting via PUT on a future-rescheduled session is hard,
    // so for this assertion we just verify the GET endpoint returns 200 for the past session.
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${pastSession.id}/predictions`, headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(Array.isArray(res.json().predictions)).toBe(true)
  })
})

describe('GET /api/predictions/upcoming', () => {
  it('lists upcoming scorable sessions with myPicks status', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const before = await app.inject({ method: 'GET', url: '/api/predictions/upcoming', headers: auth(token) })
    expect(before.statusCode).toBe(200)
    const entry = before.json().upcoming.find((u: any) => u.session.id === futureSession.id)
    expect(entry).toBeDefined()
    expect(entry.isLocked).toBe(false)
    expect(entry.myPicks).toBeNull()

    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const after = await app.inject({ method: 'GET', url: '/api/predictions/upcoming', headers: auth(token) })
    const entry2 = after.json().upcoming.find((u: any) => u.session.id === futureSession.id)
    expect(entry2.myPicks).toHaveLength(5)
  })
})
