import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as scores from '../../src/repo/scores.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
  })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  await standings.replaceDriverStandings(2026, [{ seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }])
  const s1 = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15), scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled',
  openf1SessionKey: null
  })
  return { s1 }
}

function bd(points: number) {
  return { perPosition: [{ position: 1, exact: true, wrongPos: false, points }], teamBonus: { applied: false, points: 0 }, rule: 't-v1' }
}

async function buildAndUser(emailHint: string) {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email: `${emailHint}-${Date.now()}@x.com`, password: 'hunter22', displayName: emailHint } })
  return { app: a, token: r.json().token as string, userId: r.json().user.id as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

describe('GET /api/leagues/:id/leaderboard', () => {
  it('member-only, sorted by points desc', async () => {
    const { s1 } = await seed()
    const owner = await buildAndUser('owner')
    const m1    = await buildAndUser('m1')
    const out   = await buildAndUser('out')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const leagueId = lc.json().league.id
    const code = lc.json().league.joinCode
    await m1.app.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m1.token), payload: { joinCode: code } })

    await scores.upsertScore(owner.userId, s1.id, 10, bd(10))
    await scores.upsertScore(m1.userId,    s1.id, 25, bd(25))
    await scores.upsertScore(out.userId,   s1.id, 99, bd(99))

    const memberView = await owner.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard`, headers: auth(owner.token) })
    expect(memberView.statusCode).toBe(200)
    const rows = memberView.json().leaderboard
    expect(rows[0]!.userId).toBe(m1.userId)
    expect(rows[0]!.pointsTotal).toBe(25)
    expect(rows[1]!.userId).toBe(owner.userId)
    expect(rows.length).toBe(2)  // 'out' not in league

    const outsiderView = await out.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard`, headers: auth(out.token) })
    expect(outsiderView.statusCode).toBe(403)
  })

  it('season filter via ?season=YYYY', async () => {
    const { s1 } = await seed()
    const owner = await buildAndUser('o')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'LX' } })
    const leagueId = lc.json().league.id
    await scores.upsertScore(owner.userId, s1.id, 10, bd(10))
    const r = await owner.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard?season=2024`, headers: auth(owner.token) })
    expect(r.statusCode).toBe(200)
    expect(r.json().leaderboard[0]!.pointsTotal).toBe(0)
  })
})

describe('GET /api/leagues/:id/leaderboard/sessions', () => {
  it('returns per-session per-member rows', async () => {
    const { s1 } = await seed()
    const owner = await buildAndUser('o')
    const m1 = await buildAndUser('m')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'LS' } })
    const leagueId = lc.json().league.id
    const code = lc.json().league.joinCode
    await m1.app.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m1.token), payload: { joinCode: code } })
    await scores.upsertScore(owner.userId, s1.id, 10, bd(10))
    await scores.upsertScore(m1.userId,    s1.id, 7,  bd(7))

    const r = await owner.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard/sessions`, headers: auth(owner.token) })
    expect(r.statusCode).toBe(200)
    const arr = r.json().sessions
    expect(arr).toHaveLength(1)
    expect(arr[0]!.members).toHaveLength(2)
  })
})

describe('GET /api/users/me/scores', () => {
  it('returns caller score history', async () => {
    const { s1 } = await seed()
    const me = await buildAndUser('me')
    await scores.upsertScore(me.userId, s1.id, 7, bd(7))
    const r = await me.app.inject({ method: 'GET', url: '/api/users/me/scores', headers: auth(me.token) })
    expect(r.statusCode).toBe(200)
    expect(r.json().scores).toHaveLength(1)
    expect(r.json().scores[0]!.pointsTotal).toBe(7)
  })
})
