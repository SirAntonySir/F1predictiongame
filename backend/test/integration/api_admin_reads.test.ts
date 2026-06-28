import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as leagueMembers from '../../src/repo/leagueMembers.js'

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
