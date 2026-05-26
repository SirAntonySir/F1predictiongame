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
  for (const c of ['red_bull', 'mercedes']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const code of ['VER', 'HAM']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 50, wins: 2, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 10, wins: 0, constructorId: 'mercedes' },
  ])
  await standings.replaceConstructorStandings(2026, [
    { seasonYear: 2026, constructorId: 'red_bull', position: 1, points: 60, wins: 2 },
    { seasonYear: 2026, constructorId: 'mercedes', position: 2, points: 10, wins: 0 },
  ])
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  // Lock the questionnaire in the future so we can still write picks during the test.
  await sessions.upsertSession({
    eventId: ev.id, type: 'fp1',
    scheduledStart: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000 + 7200000),
    status: 'scheduled', openf1SessionKey: null,
  })
}

async function buildAndUser(emailHint: string) {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({
    method: 'POST', url: '/api/auth/signup',
    payload: { email: `${emailHint}-${Date.now()}-${Math.random()}@x.com`, password: 'hunter22', displayName: emailHint },
  })
  return { app: a, token: r.json().token as string, userId: r.json().user.id as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

describe('GET /api/leagues/:id/preseason', () => {
  it('returns my categories + standings + aggregated leaderboard', async () => {
    await seedFuture()
    const me = await buildAndUser('me')
    const other = await buildAndUser('other')
    const lc = await me.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(me.token), payload: { name: 'L' } })
    const leagueId = lc.json().league.id
    const joinCode = lc.json().league.joinCode
    await other.app.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(other.token), payload: { joinCode } })

    await me.app.inject({
      method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(me.token),
      payload: { driverCode: 'VER', constructorId: 'red_bull' },
    })
    await other.app.inject({
      method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(other.token),
      payload: { driverCode: 'HAM', constructorId: 'mercedes' },
    })

    const res = await me.app.inject({
      method: 'GET', url: `/api/leagues/${leagueId}/preseason`, headers: auth(me.token),
    })
    expect(res.statusCode).toBe(200)
    const body = res.json() as any
    expect(body.seasonYear).toBe(2026)
    expect(body.me.categories).toHaveLength(6)
    const wdc = body.me.categories.find((c: any) => c.category === 'wdc_wcc')
    expect(wdc.myPick.driverCode).toBe('VER')
    expect(wdc.projectedTruth.driverCode).toBe('VER')
    expect(wdc.projectedPoints).toBeGreaterThan(0)
    // surprise & disappointment have null projectedTruth
    const surprise = body.me.categories.find((c: any) => c.category === 'surprise')
    expect(surprise.projectedTruth).toBeNull()
    expect(surprise.projectedPoints).toBe(0)
    // leaderboard contains both members; aggregate-only — no picks leaked
    expect(body.leaderboard).toHaveLength(2)
    const meRow = body.leaderboard.find((r: any) => r.userId === me.userId)
    const otherRow = body.leaderboard.find((r: any) => r.userId === other.userId)
    expect(meRow.preseasonPointsProjected).toBeGreaterThan(0)
    expect(otherRow.preseasonPointsProjected).toBe(0)
    expect(meRow).not.toHaveProperty('picks')
    expect(meRow).not.toHaveProperty('myPick')
  })

  it('rejects non-members', async () => {
    await seedFuture()
    const owner = await buildAndUser('owner')
    const outsider = await buildAndUser('out')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L2' } })
    const leagueId = lc.json().league.id
    const res = await outsider.app.inject({
      method: 'GET', url: `/api/leagues/${leagueId}/preseason`, headers: auth(outsider.token),
    })
    expect(res.statusCode).toBe(403)
  })
})
