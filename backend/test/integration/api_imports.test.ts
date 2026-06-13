import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as predictions from '../../src/repo/predictions.js'
import * as results from '../../src/repo/results.js'
import { getDb } from '../../src/db/client.js'
import { prediction } from '../../src/db/schema.js'
import { eq, and } from 'drizzle-orm'

// Common seed: one season, one race event, one race session, one driver, one
// constructor. Race session is needed for the predictions endpoint to score.
async function seed() {
  await seasons.upsertSeason({ year: 2024, isCurrent: false })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain GP', circuitName: 'BIC',
    country: 'BH', hasSprint: false
  })
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  await constructors.upsertConstructor({
    id: 'ferrari', name: 'Ferrari', nationality: null, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  for (const code of ['VER','NOR','LEC','HAM','RUS']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: code, nationality: null,
      permanentNumber: null, wikipediaUrl: null, imageUrl: null,
      imageUrlOverride: null, headshotUrl: null
    })
  }
  const raceSession = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2024, 2, 2, 15),
    scheduledEnd:   new Date(2024, 2, 2, 17),
    status: 'finished', openf1SessionKey: null
  })
  // Add results so score-preview can run.
  await results.replaceForSession(raceSession.id, [
    { sessionId: raceSession.id, position: 1, driverCode: 'VER', driverName: 'VER', constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 2, driverCode: 'NOR', driverName: 'NOR', constructorId: 'ferrari',  constructorName: 'Ferrari',  raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 3, driverCode: 'LEC', driverName: 'LEC', constructorId: 'ferrari',  constructorName: 'Ferrari',  raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 4, driverCode: 'HAM', driverName: 'HAM', constructorId: 'ferrari',  constructorName: 'Ferrari',  raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 5, driverCode: 'RUS', driverName: 'RUS', constructorId: 'ferrari',  constructorName: 'Ferrari',  raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
  ])
  return { ev, raceSession }
}

async function newApp() {
  return buildApp({ scheduler: null } as any)
}

async function signup(app: Awaited<ReturnType<typeof newApp>>, hint: string) {
  const r = await app.inject({
    method: 'POST', url: '/api/auth/signup',
    payload: { email: `${hint}-${Date.now()}-${Math.random().toString(36).slice(2,8)}@x.com`, password: 'hunter22', displayName: hint }
  })
  return { token: r.json().token as string, userId: r.json().user.id as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

async function makeLeagueAndMembers(app: Awaited<ReturnType<typeof newApp>>) {
  const owner  = await signup(app, 'owner')
  const member = await signup(app, 'member')
  const outsider = await signup(app, 'outsider')
  const lc = await app.inject({
    method: 'POST', url: '/api/leagues',
    headers: auth(owner.token), payload: { name: 'TestL' }
  })
  const leagueId = lc.json().league.id as string
  const joinCode = lc.json().league.joinCode as string
  await app.inject({
    method: 'POST', url: '/api/leagues/join',
    headers: auth(member.token), payload: { joinCode }
  })
  return { leagueId, owner, member, outsider }
}

describe('GET /api/leagues/:id/imports/schema', () => {
  it('returns a populated template for the owner', async () => {
    const { raceSession } = await seed()
    const app = await newApp()
    const { leagueId, owner } = await makeLeagueAndMembers(app)

    const r = await app.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/imports/schema?season=2024`,
      headers: auth(owner.token)
    })
    expect(r.statusCode).toBe(200)
    const j = r.json()
    expect(j.schemaVersion).toBe(1)
    expect(j.seasonYear).toBe(2024)
    expect(j.members.length).toBe(2)
    expect(j.drivers).toContain('VER')
    expect(j.sessions.some((s: any) => s.sessionId === raceSession.id)).toBe(true)
    expect(j.predictions).toEqual([])
  })

  it('rejects non-owner with 403', async () => {
    await seed()
    const app = await newApp()
    const { leagueId, member, outsider } = await makeLeagueAndMembers(app)
    const r1 = await app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/imports/schema?season=2024`, headers: auth(member.token) })
    expect(r1.statusCode).toBe(403)
    const r2 = await app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/imports/schema?season=2024`, headers: auth(outsider.token) })
    expect(r2.statusCode).toBe(403)
  })

  it('404s for an unbootstrapped season', async () => {
    await seed()
    const app = await newApp()
    const { leagueId, owner } = await makeLeagueAndMembers(app)
    const r = await app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/imports/schema?season=2099`, headers: auth(owner.token) })
    expect(r.statusCode).toBe(404)
  })
})

describe('POST /api/leagues/:id/imports', () => {
  function body(overrides: any = {}) {
    return {
      schemaVersion: 1,
      league: { id: '00000000-0000-0000-0000-000000000000', name: 'TestL' },
      seasonYear: 2024,
      overwrite: false,
      predictions: [],
      ...overrides
    }
  }

  it('dryRun returns preview with score and does not write', async () => {
    const { raceSession } = await seed()
    const app = await newApp()
    const { leagueId, owner, member } = await makeLeagueAndMembers(app)
    const payload = body({
      league: { id: leagueId, name: 'TestL' },
      predictions: [{
        userId: member.userId,
        sessionId: raceSession.id,
        picks: [
          { position: 1, driverCode: 'VER' },
          { position: 2, driverCode: 'NOR' },
          { position: 3, driverCode: 'LEC' },
          { position: 4, driverCode: 'HAM' },
          { position: 5, driverCode: 'RUS' }
        ]
      }]
    })
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: { ...auth(owner.token), 'content-type': 'application/json' },
      payload
    })
    expect(r.statusCode).toBe(200)
    const j = r.json()
    expect(j.dryRun).toBe(true)
    expect(j.applied.predictions).toBe(1)
    expect(j.plan.length).toBe(1)
    // All 5 picks exact + team bonus (P1 winner pick from red_bull family) →
    // 5*3 = 15 (no team bonus since picked driver = winner, but constructor
    // matches → +2). previewPoints should be a positive number.
    expect(j.scorePreview.length).toBe(1)
    expect(j.scorePreview[0].addedPoints).toBeGreaterThan(0)
    // No actual prediction row written.
    const db = getDb()
    const rows = await db.select().from(prediction)
      .where(and(eq(prediction.userId, member.userId), eq(prediction.sessionId, raceSession.id)))
    expect(rows.length).toBe(0)
  })

  it('applies the import with source=import and audits the row', async () => {
    const { raceSession } = await seed()
    const app = await newApp()
    const { leagueId, owner, member } = await makeLeagueAndMembers(app)
    const payload = body({
      league: { id: leagueId, name: 'TestL' },
      predictions: [{
        userId: member.userId,
        sessionId: raceSession.id,
        picks: [
          { position: 1, driverCode: 'VER' },
          { position: 2, driverCode: 'NOR' },
          { position: 3, driverCode: 'LEC' },
          { position: 4, driverCode: 'HAM' },
          { position: 5, driverCode: 'RUS' }
        ]
      }]
    })
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: { ...auth(owner.token), 'content-type': 'application/json' },
      payload
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().applied.predictions).toBe(1)
    expect(r.json().importId).toBeDefined()
    const db = getDb()
    const [row] = await db.select().from(prediction)
      .where(and(eq(prediction.userId, member.userId), eq(prediction.sessionId, raceSession.id)))
    expect(row).toBeDefined()
    expect(row!.source).toBe('import')
    expect(row!.importedBy).toBe(owner.userId)

    // Audit list shows the import.
    const audit = await app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/imports`, headers: auth(member.token) })
    expect(audit.statusCode).toBe(200)
    expect(audit.json().length).toBe(1)
    expect(audit.json()[0].appliedCount).toBe(1)
  })

  it('refuses to overwrite an existing in-app pick without overwrite=true', async () => {
    const { raceSession } = await seed()
    const app = await newApp()
    const { leagueId, owner, member } = await makeLeagueAndMembers(app)
    // Member already has an in-app prediction.
    await predictions.upsertPredictionWithPicks(member.userId, raceSession.id, [
      { position: 1, driverCode: 'NOR' }, { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'HAM' }, { position: 4, driverCode: 'LEC' },
      { position: 5, driverCode: 'RUS' }
    ])
    const payload = body({
      league: { id: leagueId, name: 'TestL' },
      predictions: [{
        userId: member.userId, sessionId: raceSession.id,
        picks: [
          { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' },
          { position: 3, driverCode: 'LEC' }, { position: 4, driverCode: 'HAM' },
          { position: 5, driverCode: 'RUS' }
        ]
      }]
    })
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: { ...auth(owner.token), 'content-type': 'application/json' }, payload
    })
    expect(r.statusCode).toBe(409)
    // Existing pick untouched.
    const db = getDb()
    const [row] = await db.select().from(prediction)
      .where(and(eq(prediction.userId, member.userId), eq(prediction.sessionId, raceSession.id)))
    expect(row!.source).toBe('app')

    // Now retry with overwrite=true → succeeds.
    const r2 = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: { ...auth(owner.token), 'content-type': 'application/json' },
      payload: { ...payload, overwrite: true }
    })
    expect(r2.statusCode).toBe(200)
    const [row2] = await db.select().from(prediction)
      .where(and(eq(prediction.userId, member.userId), eq(prediction.sessionId, raceSession.id)))
    expect(row2!.source).toBe('import')
  })

  it('refuses cross-league userId (foreign user not in league)', async () => {
    const { raceSession } = await seed()
    const app = await newApp()
    const { leagueId, owner, outsider } = await makeLeagueAndMembers(app)
    const payload = body({
      league: { id: leagueId, name: 'TestL' },
      predictions: [{
        userId: outsider.userId, sessionId: raceSession.id,
        picks: [
          { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' },
          { position: 3, driverCode: 'LEC' }, { position: 4, driverCode: 'HAM' },
          { position: 5, driverCode: 'RUS' }
        ]
      }]
    })
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: { ...auth(owner.token), 'content-type': 'application/json' }, payload
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().applied.predictions).toBe(0)
    expect(r.json().skipped.length).toBe(1)
    expect(r.json().skipped[0].reason).toContain('not a league member')
  })

  it('rejects non-owner with 403', async () => {
    await seed()
    const app = await newApp()
    const { leagueId, member } = await makeLeagueAndMembers(app)
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: { ...auth(member.token), 'content-type': 'application/json' },
      payload: body({ league: { id: leagueId, name: 'TestL' } })
    })
    expect(r.statusCode).toBe(403)
  })
})
