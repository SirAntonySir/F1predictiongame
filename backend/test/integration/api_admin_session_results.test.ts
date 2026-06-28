import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: null })
  for (const c of [['red_bull', 'Red Bull'], ['ferrari', 'Ferrari']]) {
    await constructors.upsertConstructor({ id: c[0], name: c[1], nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const d of ['VER', 'LEC']) {
    await drivers.upsertDriver({ code: d, givenName: d, familyName: d, nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  await results.insertResult({ sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: 'Finished', points: 25, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null })
  return ses.id
}

describe('admin session result writes', () => {
  let sid: number
  beforeEach(async () => { sid = await seed() })

  it('requires the admin token', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/1`, payload: { points: 18 } })
    expect(r.statusCode).toBe(401)
    await app.close()
  })

  it('PATCH edits a row and rescores', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/1`, headers: TOKEN, payload: { points: 18, status: 'Penalty' } })
    expect(r.statusCode).toBe(200)
    expect(r.json().result.points).toBe(18)
    expect(r.json().result.status).toBe('Penalty')
    expect(r.json().rescored).toBeDefined()
    const got = await results.getResult(sid, 1)
    expect(got?.points).toBe(18)
    await app.close()
  })

  it('PATCH rejects an unknown driver code', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/1`, headers: TOKEN, payload: { driverCode: 'NOPE' } })
    expect(r.statusCode).toBe(422)
    await app.close()
  })

  it('PATCH 404s a missing row', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/9`, headers: TOKEN, payload: { points: 1 } })
    expect(r.statusCode).toBe(404)
    await app.close()
  })

  it('POST adds a row, DELETE removes it', async () => {
    const app = await buildApp({ scheduler: null })
    const add = await app.inject({ method: 'POST', url: `/admin/sessions/${sid}/results`, headers: TOKEN, payload: { position: 2, driverCode: 'LEC', driverName: 'Charles Leclerc', constructorId: 'ferrari', constructorName: 'Ferrari', points: 18 } })
    expect(add.statusCode).toBe(200)
    expect(await results.getResult(sid, 2)).not.toBeNull()

    const dup = await app.inject({ method: 'POST', url: `/admin/sessions/${sid}/results`, headers: TOKEN, payload: { position: 2, driverCode: 'LEC', driverName: 'X', constructorId: 'ferrari', constructorName: 'Ferrari' } })
    expect(dup.statusCode).toBe(409)

    const del = await app.inject({ method: 'DELETE', url: `/admin/sessions/${sid}/results/2`, headers: TOKEN })
    expect(del.statusCode).toBe(200)
    expect(await results.getResult(sid, 2)).toBeNull()
    await app.close()
  })
})
