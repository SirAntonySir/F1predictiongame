import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as leagueMembers from '../../src/repo/leagueMembers.js'
import * as sessions from '../../src/repo/sessions.js'
import * as events from '../../src/repo/events.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictions from '../../src/repo/predictions.js'
import * as results from '../../src/repo/results.js'
import * as constructors from '../../src/repo/constructors.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

describe('GET /admin/leagues', () => {
  it('requires the admin token', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/leagues' })
    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('lists all leagues with owner name and member count', async () => {
    const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'Owner' })
    const member = await users.insertUser({ email: 'm@x.com', passwordHash: 'h', displayName: 'Member' })
    const lg = await leagues.createLeagueWithOwner({ name: 'My League', ownerUserId: owner.id, joinCode: 'ABC123' })
    await leagueMembers.add(lg.id, member.id)

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/leagues', headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.leagues).toHaveLength(1)
    expect(body.leagues[0]).toMatchObject({
      id: lg.id, name: 'My League', ownerUserId: owner.id,
      ownerDisplayName: 'Owner', memberCount: 2, joinCode: 'ABC123', hasPassword: false
    })
    await app.close()
  })

  it('returns one league with its members', async () => {
    const owner = await users.insertUser({ email: 'o2@x.com', passwordHash: 'h', displayName: 'Owner2' })
    const member = await users.insertUser({ email: 'm2@x.com', passwordHash: 'h', displayName: 'Member2' })
    const lg = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: owner.id, joinCode: 'DEF456' })
    await leagueMembers.add(lg.id, member.id)

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/admin/leagues/${lg.id}`, headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.league.id).toBe(lg.id)
    expect(body.members).toHaveLength(2)
    const ownerRow = body.members.find((m: any) => m.userId === owner.id)
    expect(ownerRow).toMatchObject({ role: 'owner', email: 'o2@x.com', displayName: 'Owner2' })
    expect(body.members.find((m: any) => m.userId === member.id).role).toBe('member')
    await app.close()
  })

  it('404s an unknown league', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({
      method: 'GET',
      url: '/admin/leagues/00000000-0000-0000-0000-000000000000',
      headers: TOKEN
    })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})

describe('GET /admin/users', () => {
  it('lists users with league counts and supports search', async () => {
    const a = await users.insertUser({ email: 'alice@x.com', passwordHash: 'h', displayName: 'Alice' })
    await users.insertUser({ email: 'bob@x.com', passwordHash: 'h', displayName: 'Bob' })
    await leagues.createLeagueWithOwner({ name: 'AL', ownerUserId: a.id, joinCode: 'AAA111' })

    const app = await buildApp({ scheduler: null })
    const all = await app.inject({ method: 'GET', url: '/admin/users', headers: TOKEN })
    expect(all.statusCode).toBe(200)
    expect(all.json().total).toBe(2)
    const alice = all.json().users.find((u: any) => u.id === a.id)
    expect(alice.leagueCount).toBe(1)

    const search = await app.inject({ method: 'GET', url: '/admin/users?query=bob', headers: TOKEN })
    expect(search.json().total).toBe(1)
    expect(search.json().users[0].displayName).toBe('Bob')
    await app.close()
  })

  it('returns user detail with leagues and prediction count', async () => {
    const u = await users.insertUser({ email: 'd@x.com', passwordHash: 'h', displayName: 'Dee' })
    await leagues.createLeagueWithOwner({ name: 'DL', ownerUserId: u.id, joinCode: 'DDD111' })
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
    const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'scheduled', openf1SessionKey: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [{ position: 1, driverCode: 'VER' }])

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/admin/users/${u.id}`, headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.user.email).toBe('d@x.com')
    expect(body.user.leagues).toHaveLength(1)
    expect(body.user.leagues[0].role).toBe('owner')
    expect(body.user.predictionCount).toBe(1)
    await app.close()
  })

  it('404s an unknown user', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/users/00000000-0000-0000-0000-000000000000', headers: TOKEN })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})

describe('GET /admin/sessions', () => {
  it('lists sessions with event metadata, result count and provisional flag', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'Bahrain GP', circuitName: 'Sakhir', country: 'BH', hasSprint: false })
    const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: 999 })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await results.replaceForSession(ses.id, [{
      sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'Max Verstappen',
      constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: 'Finished',
      points: 25, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null
    }], 'openf1')

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/sessions?season=2026', headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const rows = res.json().sessions
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({
      id: ses.id, seasonYear: 2026, round: 1, eventName: 'Bahrain GP',
      type: 'race', status: 'finished', resultCount: 1, provisional: true
    })
    await app.close()
  })
})

describe('GET /admin/predictions', () => {
  it('requires at least one filter', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/predictions', headers: TOKEN })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('lists predictions for a session with picks and display names', async () => {
    const u = await users.insertUser({ email: 'p@x.com', passwordHash: 'h', displayName: 'Pat' })
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
    const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'scheduled', openf1SessionKey: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [{ position: 1, driverCode: 'VER' }])

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/admin/predictions?sessionId=${ses.id}`, headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const rows = res.json().predictions
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({ userId: u.id, displayName: 'Pat', sessionId: ses.id, source: 'app' })
    expect(rows[0].picks).toEqual([{ position: 1, driverCode: 'VER' }])
    await app.close()
  })
})

describe('GET /admin/crawl/status', () => {
  it('reports tick status, pending candidates and provisional sessions', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
    // A finished session with an openf1-sourced result => provisional.
    const fin = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: 7 })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await results.replaceForSession(fin.id, [{
      sessionId: fin.id, position: 1, driverCode: 'VER', driverName: 'Max Verstappen',
      constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: 'Finished',
      points: 25, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null
    }], 'openf1')

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/crawl/status', headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.lastTickAt).toBeNull()
    expect(Array.isArray(body.pendingCandidates)).toBe(true)
    expect(body.provisionalSessions.map((s: any) => s.id)).toContain(fin.id)
    await app.close()
  })
})
