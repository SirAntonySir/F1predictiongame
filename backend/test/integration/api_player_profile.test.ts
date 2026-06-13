import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as predictions from '../../src/repo/predictions.js'
import * as results from '../../src/repo/results.js'
import * as scores from '../../src/repo/scores.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain GP', circuitName: 'BIC',
    country: 'BH', hasSprint: false
  })
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  for (const code of ['VER','NOR','LEC','HAM','RUS']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: code, nationality: null,
      permanentNumber: null, wikipediaUrl: null, imageUrl: null,
      imageUrlOverride: null, headshotUrl: null
    })
  }
  // Session in the past so locked-pick filter accepts it.
  const raceSession = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() - 86_400_000),
    scheduledEnd:   new Date(Date.now() - 80_000_000),
    status: 'finished', openf1SessionKey: null
  })
  await results.replaceForSession(raceSession.id, [
    { sessionId: raceSession.id, position: 1, driverCode: 'VER', driverName: 'VER', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 2, driverCode: 'NOR', driverName: 'NOR', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 3, driverCode: 'LEC', driverName: 'LEC', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 4, driverCode: 'HAM', driverName: 'HAM', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null },
    { sessionId: raceSession.id, position: 5, driverCode: 'RUS', driverName: 'RUS', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
  ])
  return { raceSession }
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

async function leagueOf(app: Awaited<ReturnType<typeof newApp>>) {
  const owner    = await signup(app, 'owner')
  const member   = await signup(app, 'member')
  const outsider = await signup(app, 'outsider')
  const lc = await app.inject({
    method: 'POST', url: '/api/leagues',
    headers: auth(owner.token), payload: { name: 'TestL' }
  })
  const leagueId = lc.json().league.id as string
  const code = lc.json().league.joinCode as string
  await app.inject({
    method: 'POST', url: '/api/leagues/join',
    headers: auth(member.token), payload: { joinCode: code }
  })
  return { leagueId, owner, member, outsider }
}

describe('GET /api/leagues/:id/players/:userId', () => {
  it('returns the composite payload for a league member viewing another member', async () => {
    const { raceSession } = await seed()
    const app = await newApp()
    const { leagueId, owner, member } = await leagueOf(app)

    // Member has a prediction on the past race.
    await predictions.upsertPredictionWithPicks(member.userId, raceSession.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' },
      { position: 3, driverCode: 'LEC' }, { position: 4, driverCode: 'HAM' },
      { position: 5, driverCode: 'RUS' }
    ])
    await scores.upsertScore(member.userId, raceSession.id, 17, {
      perPosition: [
        { position: 1, exact: true,  wrongPos: false, points: 3, driverCode: 'VER' },
        { position: 2, exact: true,  wrongPos: false, points: 3, driverCode: 'NOR' },
        { position: 3, exact: true,  wrongPos: false, points: 3, driverCode: 'LEC' },
        { position: 4, exact: true,  wrongPos: false, points: 3, driverCode: 'HAM' },
        { position: 5, exact: true,  wrongPos: false, points: 3, driverCode: 'RUS' }
      ],
      teamBonus: { applied: true, points: 2 }, rule: 'race-v1'
    })

    const r = await app.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/players/${member.userId}`,
      headers: auth(owner.token)
    })
    expect(r.statusCode).toBe(200)
    const j = r.json()
    expect(j.player.displayName).toBe('member')
    expect(j.player.isSelf).toBe(false)
    expect(j.season.year).toBe(2026)
    expect(j.standing.pointsTotal).toBe(17)
    expect(j.recentForm.length).toBe(1)
    expect(j.recentForm[0].points).toBe(17)
    expect(j.recentForm[0].glyphs).toEqual(['exact','exact','exact','exact','exact','teamBonus'])
    expect(j.insights.mostPickedP1).toEqual({ driverCode: 'VER', count: 1 })
    expect(j.insights.exactHitRate).toBe(1)
    expect(j.insights.bestWeekend.points).toBe(17)
    expect(j.insights.bestWeekend.round).toBe(1)
    expect(j.insights.bestWeekend.sessions).toBe(1)
    expect(j.pickLog.length).toBe(1)
    expect(j.pickLog[0].picks.length).toBe(5)
    expect(j.pickLog[0].topResults[0].driverCode).toBe('VER')
  })

  it('isSelf is true when viewing your own profile', async () => {
    await seed()
    const app = await newApp()
    const { leagueId, owner } = await leagueOf(app)
    const r = await app.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/players/${owner.userId}`,
      headers: auth(owner.token)
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().player.isSelf).toBe(true)
  })

  it('403 when caller is not in the league', async () => {
    await seed()
    const app = await newApp()
    const { leagueId, member, outsider } = await leagueOf(app)
    const r = await app.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/players/${member.userId}`,
      headers: auth(outsider.token)
    })
    expect(r.statusCode).toBe(403)
  })

  it('404 when target is not in the league', async () => {
    await seed()
    const app = await newApp()
    const { leagueId, owner, outsider } = await leagueOf(app)
    const r = await app.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/players/${outsider.userId}`,
      headers: auth(owner.token)
    })
    expect(r.statusCode).toBe(404)
  })

  it('locked-pick filter excludes predictions on future sessions', async () => {
    // Same seed, but add an extra future session — member has picks on it,
    // but they shouldn't appear in pickLog because scheduledStart is in the
    // future.
    const { raceSession } = await seed()
    const futureEv = await events.upsertEvent({
      seasonYear: 2026, round: 2, name: 'Saudi GP', circuitName: 'Jeddah',
      country: 'SA', hasSprint: false
    })
    const futureSession = await sessions.upsertSession({
      eventId: futureEv.id, type: 'race',
      scheduledStart: new Date(Date.now() + 7 * 86_400_000),
      scheduledEnd:   new Date(Date.now() + 7 * 86_400_000 + 7200_000),
      status: 'scheduled', openf1SessionKey: null
    })
    const app = await newApp()
    const { leagueId, owner, member } = await leagueOf(app)
    await predictions.upsertPredictionWithPicks(member.userId, raceSession.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' },
      { position: 3, driverCode: 'LEC' }, { position: 4, driverCode: 'HAM' },
      { position: 5, driverCode: 'RUS' }
    ])
    await predictions.upsertPredictionWithPicks(member.userId, futureSession.id, [
      { position: 1, driverCode: 'HAM' }, { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'NOR' }, { position: 4, driverCode: 'LEC' },
      { position: 5, driverCode: 'RUS' }
    ])
    const r = await app.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/players/${member.userId}`,
      headers: auth(owner.token)
    })
    expect(r.statusCode).toBe(200)
    const j = r.json()
    // Only the past race appears.
    expect(j.pickLog.length).toBe(1)
    expect(j.pickLog[0].sessionId).toBe(raceSession.id)
    // mostPickedP1 still counts BOTH P1 picks (across all in-season picks,
    // not just locked ones) — design choice. VER once, HAM once.
    expect(j.insights.mostPickedP1).not.toBeNull()
  })
})
