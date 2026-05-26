import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'

async function seedFuture() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const code of ['VER', 'HAM', 'NOR']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 0, wins: 0, constructorId: 'mercedes' },
    { seasonYear: 2026, driverCode: 'NOR', position: 3, points: 0, wins: 0, constructorId: 'mclaren' }
  ])
  await standings.replaceConstructorStandings(2026, [
    { seasonYear: 2026, constructorId: 'red_bull', position: 1, points: 0, wins: 0 },
    { seasonYear: 2026, constructorId: 'mercedes', position: 2, points: 0, wins: 0 },
    { seasonYear: 2026, constructorId: 'mclaren',  position: 3, points: 0, wins: 0 }
  ])
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  // Lock in the future
  await sessions.upsertSession({
    eventId: ev.id, type: 'fp1',
    scheduledStart: new Date(Date.now() + 24 * 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 25 * 60 * 60 * 1000), status: 'scheduled',
  openf1SessionKey: null
  })
}

async function seedPast() {
  await seedFuture()
  const ev = await events.getByRound(2026, 1)
  // Add an FP1 in the past instead
  await sessions.upsertSession({
    eventId: ev!.id, type: 'fp1',
    scheduledStart: new Date(Date.now() - 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() - 30 * 60 * 1000), status: 'scheduled',
  openf1SessionKey: null
  })
}

async function buildAndUser() {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email: `u-${Date.now()}-${Math.random()}@x.com`, password: 'hunter22', displayName: 'U' } })
  return { app: a, token: r.json().token as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

describe('PUT /api/preseason/:category', () => {
  it('submits a single-pick category', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(token),
      payload: { driverCode: 'VER', constructorId: 'red_bull' }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().pick.driverCode).toBe('VER')
  })

  it('accepts driver-only pick', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/poles', headers: auth(token),
      payload: { driverCode: 'VER' }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().pick.constructorId).toBeNull()
  })

  it('rejects with 422 when neither driver nor team provided', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/poles', headers: auth(token),
      payload: {}
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects unknown category with 400', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/bogus', headers: auth(token),
      payload: { driverCode: 'VER' }
    })
    expect(res.statusCode).toBe(400)
  })

  it('rejects driver not in season with 422', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    await drivers.upsertDriver({ code: 'OLD', givenName: 'O', familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/dnf', headers: auth(token),
      payload: { driverCode: 'OLD' }
    })
    expect(res.statusCode).toBe(422)
  })

  it('409 after lock', async () => {
    await seedPast()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(token),
      payload: { driverCode: 'VER' }
    })
    expect(res.statusCode).toBe(409)
  })
})

describe('PUT /api/preseason/standings/drivers', () => {
  it('accepts a [1..N] driver ordering', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/standings/drivers', headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' },
        { position: 2, driverCode: 'HAM' },
        { position: 3, driverCode: 'NOR' }
      ] }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().picks).toHaveLength(3)
  })

  it('rejects gap in positions', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/standings/drivers', headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' },
        { position: 3, driverCode: 'HAM' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects duplicate driver', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/standings/drivers', headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' },
        { position: 2, driverCode: 'VER' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })
})

describe('GET /api/preseason/my', () => {
  it('returns the complete questionnaire state', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(token), payload: { driverCode: 'VER', constructorId: 'red_bull' } })
    const res = await app.inject({ method: 'GET', url: '/api/preseason/my', headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().wdc_wcc.driverCode).toBe('VER')
    expect(res.json().surprise).toBeNull()
    expect(res.json().isLocked).toBe(false)
    expect(res.json().locksAt).not.toBeNull()
  })
})

describe('DELETE /api/preseason/:category', () => {
  it('removes the pick before lock', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: '/api/preseason/dnf', headers: auth(token), payload: { driverCode: 'VER' } })
    const del = await app.inject({ method: 'DELETE', url: '/api/preseason/dnf', headers: auth(token) })
    expect(del.statusCode).toBe(200)
    const my = await app.inject({ method: 'GET', url: '/api/preseason/my', headers: auth(token) })
    expect(my.json().dnf).toBeNull()
  })
})

describe('GET /api/seasons/:year/preseason-truth', () => {
  it('403 before lock', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: '/api/seasons/2026/preseason-truth', headers: auth(token) })
    expect(res.statusCode).toBe(403)
  })

  it('200 after lock returns null subjective initially', async () => {
    await seedPast()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: '/api/seasons/2026/preseason-truth', headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().subjective).toBeNull()
  })
})
