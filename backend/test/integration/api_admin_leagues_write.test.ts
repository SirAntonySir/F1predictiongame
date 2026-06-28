import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as leagueMembers from '../../src/repo/leagueMembers.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'Owner' })
  const member = await users.insertUser({ email: 'm@x.com', passwordHash: 'h', displayName: 'Member' })
  const lg = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: owner.id, joinCode: 'AAA111' })
  await leagueMembers.add(lg.id, member.id)
  return { lg, owner, member }
}

describe('admin league writes', () => {
  it('requires the admin token', async () => {
    const { lg } = await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/leagues/${lg.id}`, payload: { name: 'X' } })
    expect(r.statusCode).toBe(401)
    await app.close()
  })

  it('renames and sets/clears the password', async () => {
    const { lg } = await seed()
    const app = await buildApp({ scheduler: null })
    let r = await app.inject({ method: 'PATCH', url: `/admin/leagues/${lg.id}`, headers: TOKEN, payload: { name: 'Renamed', password: 'secret' } })
    expect(r.statusCode).toBe(200)
    expect(r.json().league.name).toBe('Renamed')
    expect(r.json().league.hasPassword).toBe(true)
    r = await app.inject({ method: 'PATCH', url: `/admin/leagues/${lg.id}`, headers: TOKEN, payload: { password: null } })
    expect(r.statusCode).toBe(200)
    expect(r.json().league.hasPassword).toBe(false)
    await app.close()
  })

  it('regenerates the join code', async () => {
    const { lg } = await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'POST', url: `/admin/leagues/${lg.id}/regenerate-code`, headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(typeof r.json().joinCode).toBe('string')
    expect(r.json().joinCode).not.toBe('AAA111')
    await app.close()
  })

  it('kicks a member but refuses to kick the owner (409)', async () => {
    const { lg, owner, member } = await seed()
    const app = await buildApp({ scheduler: null })
    const kick = await app.inject({ method: 'DELETE', url: `/admin/leagues/${lg.id}/members/${member.id}`, headers: TOKEN })
    expect(kick.statusCode).toBe(200)
    expect(await leagueMembers.isMember(lg.id, member.id)).toBe(false)

    const kickOwner = await app.inject({ method: 'DELETE', url: `/admin/leagues/${lg.id}/members/${owner.id}`, headers: TOKEN })
    expect(kickOwner.statusCode).toBe(409)
    await app.close()
  })

  it('deletes a league, and 404s an unknown league', async () => {
    const { lg } = await seed()
    const app = await buildApp({ scheduler: null })
    const del = await app.inject({ method: 'DELETE', url: `/admin/leagues/${lg.id}`, headers: TOKEN })
    expect(del.statusCode).toBe(200)
    expect(await leagues.findById(lg.id)).toBeNull()

    const missing = await app.inject({ method: 'PATCH', url: '/admin/leagues/00000000-0000-0000-0000-000000000000', headers: TOKEN, payload: { name: 'X' } })
    expect(missing.statusCode).toBe(404)
    await app.close()
  })
})
