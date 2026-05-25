import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'

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
    expect(body.league.joinCode).toMatch(/^[A-Z0-9]{6}$/)
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
