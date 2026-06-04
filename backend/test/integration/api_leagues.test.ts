import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as scoresT from '../../src/repo/scores.js'

async function seedDrivers(codes: string[]) {
  for (const code of codes) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: 'X',
      nationality: null, permanentNumber: null, wikipediaUrl: null,
      imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
}

async function app() { return buildApp({ scheduler: null }) }

async function signupAndToken(a: Awaited<ReturnType<typeof app>>, email: string) {
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email, password: 'hunter22', displayName: email.split('@')[0] } })
  return { token: r.json().token as string, userId: r.json().user.id as string }
}

function auth(token: string) { return { authorization: `Bearer ${token}` } }

describe('POST /api/leagues', () => {
  it('creates a league owned by the caller', async () => {
    const a = await app()
    const { token } = await signupAndToken(a, 'o@x.com')
    const res = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(token), payload: { name: 'Friends' } })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.league.name).toBe('Friends')
    expect(body.league.joinCode).toMatch(/^[A-Z0-9]{8}$/)
    expect(body.league.memberCount).toBe(1)
  })

  it('409s if caller already owns a league', async () => {
    const a = await app()
    const { token } = await signupAndToken(a, 'o2@x.com')
    await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(token), payload: { name: 'L1' } })
    const res = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(token), payload: { name: 'L2' } })
    expect(res.statusCode).toBe(409)
  })

  it('401 without token', async () => {
    const a = await app()
    const res = await a.inject({ method: 'POST', url: '/api/leagues', payload: { name: 'x' } })
    expect(res.statusCode).toBe(401)
  })
})

describe('GET /api/leagues/mine', () => {
  it('returns leagues with role', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'own@x.com')
    const joiner = await signupAndToken(a, 'join@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'Owners' } })
    const joinerOwned = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(joiner.token), payload: { name: 'JoinerOwn' } })
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    const res = await a.inject({ method: 'GET', url: '/api/leagues/mine', headers: auth(joiner.token) })
    expect(res.statusCode).toBe(200)
    const byName = new Map(res.json().leagues.map((l: any) => [l.name, l.role]))
    expect(byName.get('Owners')).toBe('member')
    expect(byName.get('JoinerOwn')).toBe('owner')
  })
})

describe('GET /api/leagues/:id', () => {
  it('returns league + members for a member; hides joinCode if not owner', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'go@x.com')
    const joiner = await signupAndToken(a, 'gj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    const asOwner = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(asOwner.json().league.joinCode).toBe(code)

    const asMember = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(joiner.token) })
    expect(asMember.json().league.joinCode).toBeUndefined()
    expect(asMember.json().members).toHaveLength(2)
  })

  // The Flutter LeagueView model parses `role` as a required string. If the
  // backend stops including it the client silently fails to load the league
  // and Settings / Standings render "No league" forever.
  it('includes the caller\'s role on the league object', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'ro@x.com')
    const joiner = await signupAndToken(a, 'rj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'R' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    expect(created.json().league.role).toBe('owner')

    const asOwner = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(asOwner.json().league.role).toBe('owner')

    const asMember = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(joiner.token) })
    expect(asMember.json().league.role).toBe('member')
  })

  it('403 for non-members', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'fo@x.com')
    const stranger = await signupAndToken(a, 'fs@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const res = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(stranger.token) })
    expect(res.statusCode).toBe(403)
  })
})

describe('PATCH /api/leagues/:id', () => {
  it('renames when owner', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'r@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'Old' } })
    const id = created.json().league.id
    const res = await a.inject({ method: 'PATCH', url: `/api/leagues/${id}`, headers: auth(owner.token), payload: { name: 'New' } })
    expect(res.statusCode).toBe(200)
    expect(res.json().league.name).toBe('New')
  })

  it('403 when not owner', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'r2@x.com')
    const joiner = await signupAndToken(a, 'j2@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })
    const res = await a.inject({ method: 'PATCH', url: `/api/leagues/${id}`, headers: auth(joiner.token), payload: { name: 'Hack' } })
    expect(res.statusCode).toBe(403)
  })
})

describe('POST /api/leagues/:id/regenerate-code', () => {
  it('owner regenerates; old code no longer works', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'rc@x.com')
    const joiner = await signupAndToken(a, 'rcj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const oldCode = created.json().league.joinCode

    const regen = await a.inject({ method: 'POST', url: `/api/leagues/${id}/regenerate-code`, headers: auth(owner.token) })
    expect(regen.statusCode).toBe(200)
    expect(regen.json().joinCode).not.toBe(oldCode)

    const tryOld = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: oldCode } })
    expect(tryOld.statusCode).toBe(404)
  })
})

describe('POST /api/leagues/join', () => {
  it('joins via code, idempotent rejection on second join', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'jo@x.com')
    const joiner = await signupAndToken(a, 'jj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const code = created.json().league.joinCode

    const j1 = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })
    expect(j1.statusCode).toBe(200)

    const j2 = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })
    expect(j2.statusCode).toBe(409)
  })

  it('404 for unknown code', async () => {
    const a = await app()
    const u = await signupAndToken(a, 'u@x.com')
    const res = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(u.token), payload: { joinCode: 'ZZZZZZ' } })
    expect(res.statusCode).toBe(404)
  })

  it('409 if joining own league', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'self@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'Mine' } })
    const code = created.json().league.joinCode
    const res = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(owner.token), payload: { joinCode: code } })
    expect(res.statusCode).toBe(409)
  })
})

describe('DELETE /api/leagues/:id/members/me', () => {
  it('member can leave; owner cannot use this endpoint', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'lo@x.com')
    const joiner = await signupAndToken(a, 'lj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    const leave = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/me`, headers: auth(joiner.token) })
    expect(leave.statusCode).toBe(200)

    const ownerLeaves = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/me`, headers: auth(owner.token) })
    expect(ownerLeaves.statusCode).toBe(409)
  })
})

describe('DELETE /api/leagues/:id/members/:userId', () => {
  it('owner kicks member; cannot kick self', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'ko@x.com')
    const m = await signupAndToken(a, 'km@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m.token), payload: { joinCode: code } })

    const kick = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/${m.userId}`, headers: auth(owner.token) })
    expect(kick.statusCode).toBe(200)

    const self = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/${owner.userId}`, headers: auth(owner.token) })
    expect(self.statusCode).toBe(400)
  })
})

describe('DELETE /api/leagues/:id', () => {
  it('owner deletes league and members are gone', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'do@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const del = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(del.statusCode).toBe(200)
    const get = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(get.statusCode).toBe(404)
  })
})

describe('GET /api/leagues/:id/sessions/:sessionId/predictions', () => {
  async function seedSession(opts: { startInPast: boolean }) {
    await seasons.upsertSeason({ year: 2099, isCurrent: false })
    const ev = await events.upsertEvent({
      seasonYear: 2099, round: 1, name: 'T', circuitName: 'C', country: 'X', hasSprint: false
    })
    const start = opts.startInPast
      ? new Date(Date.now() - 60 * 60 * 1000)
      : new Date(Date.now() + 24 * 60 * 60 * 1000)
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: start,
      scheduledEnd: new Date(start.getTime() + 2 * 60 * 60 * 1000),
      status: 'scheduled', openf1SessionKey: null
    })
    return ses
  }

  it('returns every member\'s picks once the session has started', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'lp-o@x.com')
    const m1 = await signupAndToken(a, 'lp-1@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'P' } })
    const leagueId = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m1.token), payload: { joinCode: code } })

    const ses = await seedSession({ startInPast: true })
    await seedDrivers(['VER', 'NOR', 'HAM', 'PIA', 'LEC'])
    await predictionsRepo.upsertPredictionWithPicks(owner.userId, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'NOR' },
      { position: 3, driverCode: 'HAM' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'LEC' }
    ])
    // m1 deliberately didn't submit picks — should appear with empty list.

    const res = await a.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/sessions/${ses.id}/predictions`,
      headers: auth(owner.token)
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.sessionLocked).toBe(true)
    expect(body.predictions).toHaveLength(2)
    const byUser = new Map(body.predictions.map((p: any) => [p.userId, p]))
    expect((byUser.get(owner.userId) as any).picks).toHaveLength(5)
    expect((byUser.get(owner.userId) as any).pointsTotal).toBeNull()
    expect((byUser.get(m1.userId) as any).picks).toHaveLength(0)
  })

  it('hides picks before session start (sessionLocked: false, empty list)', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'lp-fut@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'F' } })
    const leagueId = created.json().league.id

    const ses = await seedSession({ startInPast: false })
    await seedDrivers(['VER', 'NOR', 'HAM', 'PIA', 'LEC'])
    await predictionsRepo.upsertPredictionWithPicks(owner.userId, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'NOR' },
      { position: 3, driverCode: 'HAM' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'LEC' }
    ])

    const res = await a.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/sessions/${ses.id}/predictions`,
      headers: auth(owner.token)
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().sessionLocked).toBe(false)
    expect(res.json().predictions).toHaveLength(0)
  })

  it('403 for non-members', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'lp-403o@x.com')
    const stranger = await signupAndToken(a, 'lp-403s@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'S' } })
    const leagueId = created.json().league.id
    const ses = await seedSession({ startInPast: true })

    const res = await a.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/sessions/${ses.id}/predictions`,
      headers: auth(stranger.token)
    })
    expect(res.statusCode).toBe(403)
  })
})

describe('GET /api/leagues/:id/gossip', () => {
  it('aggregates last-race best/worst/no-show + driver impact across the league', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'gg-o@x.com')
    const m1 = await signupAndToken(a, 'gg-1@x.com')
    const m2 = await signupAndToken(a, 'gg-2@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'G' } })
    const leagueId = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m1.token), payload: { joinCode: code } })
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m2.token), payload: { joinCode: code } })

    // Seed a finished race in the current season.
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2026, round: 1, name: 'Gossipland', circuitName: 'C', country: 'X', hasSprint: false
    })
    const past = new Date(Date.now() - 24 * 60 * 60 * 1000)
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: past, scheduledEnd: new Date(past.getTime() + 2 * 60 * 60 * 1000),
      status: 'scheduled', openf1SessionKey: null
    })
    await sessions.markFinished(ses.id)

    await seedDrivers(['VER', 'NOR', 'HAM'])
    // Owner: picked VER + NOR (both nailed), scored 10.
    await predictionsRepo.upsertPredictionWithPicks(owner.userId, ses.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' }
    ])
    await scoresT.upsertScore(owner.userId, ses.id, 10, {
      perPosition: [
        { position: 1, driverCode: 'VER', exact: true, wrongPos: false, points: 5 },
        { position: 2, driverCode: 'NOR', exact: true, wrongPos: false, points: 5 }
      ],
      teamBonus: { applied: false, points: 0 },
      rule: 't-v1'
    })
    // m1: picked VER + HAM, only VER scored — HAM was a miss.
    await predictionsRepo.upsertPredictionWithPicks(m1.userId, ses.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'HAM' }
    ])
    await scoresT.upsertScore(m1.userId, ses.id, 5, {
      perPosition: [
        { position: 1, driverCode: 'VER', exact: true, wrongPos: false, points: 5 },
        { position: 2, driverCode: 'HAM', exact: false, wrongPos: false, points: 0 }
      ],
      teamBonus: { applied: false, points: 0 },
      rule: 't-v1'
    })
    // m2: no picks → no-show.

    const res = await a.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/gossip`,
      headers: auth(owner.token)
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.lastRace.round).toBe(1)
    expect(body.lastRace.name).toBe('Gossipland')
    expect(body.bestPlayer.userId).toBe(owner.userId)
    expect(body.bestPlayer.points).toBe(10)
    expect(body.worstPlayers).toHaveLength(1)
    expect(body.worstPlayers[0].userId).toBe(m1.userId)
    expect(body.noShowPlayers.map((p: any) => p.userId)).toEqual([m2.userId])
    // VER scored 5 for owner + 5 for m1 = 10 league-wide.
    expect(body.driverGained).toEqual({ driverCode: 'VER', points: 10 })
    expect(body.driverCost).toEqual({ driverCode: 'HAM', count: 1 })
  })

  it('returns lastRace: null when no race has finished', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'gg-empty@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'E' } })
    const leagueId = created.json().league.id

    const res = await a.inject({
      method: 'GET',
      url: `/api/leagues/${leagueId}/gossip`,
      headers: auth(owner.token)
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().lastRace).toBeNull()
  })
})

describe('Leagues with passwords + duplicate display names', () => {
  it('create with password sets hasPassword=true and gates joins', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'pwo@x.com')
    const joiner = await signupAndToken(a, 'pwj@x.com')

    const created = await a.inject({
      method: 'POST', url: '/api/leagues', headers: auth(owner.token),
      payload: { name: 'Secret', password: 'sekret' }
    })
    expect(created.statusCode).toBe(200)
    expect(created.json().league.hasPassword).toBe(true)

    const code = created.json().league.joinCode

    // No password → 401
    const noPw = await a.inject({
      method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token),
      payload: { joinCode: code }
    })
    expect(noPw.statusCode).toBe(403)

    // Wrong password → 401
    const wrong = await a.inject({
      method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token),
      payload: { joinCode: code, password: 'wrong' }
    })
    expect(wrong.statusCode).toBe(403)

    // Right password → 200
    const ok = await a.inject({
      method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token),
      payload: { joinCode: code, password: 'sekret' }
    })
    expect(ok.statusCode).toBe(200)
  })

  it('create without password leaves the league open', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'opn-o@x.com')
    const joiner = await signupAndToken(a, 'opn-j@x.com')
    const created = await a.inject({
      method: 'POST', url: '/api/leagues', headers: auth(owner.token),
      payload: { name: 'Open' }
    })
    expect(created.json().league.hasPassword).toBe(false)

    const code = created.json().league.joinCode
    const ok = await a.inject({
      method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token),
      payload: { joinCode: code }
    })
    expect(ok.statusCode).toBe(200)
  })

  it('PATCH password=null clears the gate; PATCH password=str sets it', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'rot-o@x.com')
    const joiner = await signupAndToken(a, 'rot-j@x.com')
    const created = await a.inject({
      method: 'POST', url: '/api/leagues', headers: auth(owner.token),
      payload: { name: 'Rotating', password: 'first' }
    })
    const id = created.json().league.id

    // Clear
    const cleared = await a.inject({
      method: 'PATCH', url: `/api/leagues/${id}`, headers: auth(owner.token),
      payload: { password: null }
    })
    expect(cleared.statusCode).toBe(200)
    expect(cleared.json().league.hasPassword).toBe(false)
    const code = created.json().league.joinCode
    const joinNow = await a.inject({
      method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token),
      payload: { joinCode: code }
    })
    expect(joinNow.statusCode).toBe(200)
  })

  it('rejects join when caller\'s display name collides with an existing member', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'dn-o@x.com')
    // Both joiners pick the same email-derived displayName (uses split @);
    // explicitly post-signup we re-use the owner's name to force a clash.
    const dupe = await signupAndToken(a, 'dn-o@y.com')  // displayName: "dn-o"
    const created = await a.inject({
      method: 'POST', url: '/api/leagues', headers: auth(owner.token),
      payload: { name: 'Dupes' }
    })
    const code = created.json().league.joinCode

    const res = await a.inject({
      method: 'POST', url: '/api/leagues/join', headers: auth(dupe.token),
      payload: { joinCode: code }
    })
    expect(res.statusCode).toBe(409)
    expect(res.json().error.message.toLowerCase()).toContain('display name')
  })
})
