import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'

async function makeUser(email = `u-${Date.now()}-${Math.random()}@x.com`) {
  return users.insertUser({ email, passwordHash: 'h', displayName: 'U' })
}

describe('leagues repo', () => {
  it('creates a league with code and adds owner as member (transaction)', async () => {
    const owner = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'Anton League', ownerUserId: owner.id, joinCode: 'ABC123' })
    expect(l.name).toBe('Anton League')
    expect(l.joinCode).toBe('ABC123')

    const m = await members.listByLeague(l.id)
    expect(m.map((x) => x.userId)).toContain(owner.id)
  })

  it('rejects a second league from the same owner', async () => {
    const owner = await makeUser()
    await leagues.createLeagueWithOwner({ name: 'One', ownerUserId: owner.id, joinCode: 'AAA111' })
    await expect(
      leagues.createLeagueWithOwner({ name: 'Two', ownerUserId: owner.id, joinCode: 'BBB222' })
    ).rejects.toThrow(/duplicate|unique/i)
  })

  it('rejects duplicate join code', async () => {
    const o1 = await makeUser('one@x.com')
    const o2 = await makeUser('two@x.com')
    await leagues.createLeagueWithOwner({ name: 'L1', ownerUserId: o1.id, joinCode: 'CODE01' })
    await expect(
      leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: o2.id, joinCode: 'CODE01' })
    ).rejects.toThrow(/duplicate|unique/i)
  })

  it('finds a league by join code', async () => {
    const o = await makeUser()
    await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'FIND01' })
    const found = await leagues.findByJoinCode('FIND01')
    expect(found?.name).toBe('L')
  })

  it('updates league name', async () => {
    const o = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'Old', ownerUserId: o.id, joinCode: 'UPD001' })
    const updated = await leagues.updateName(l.id, 'New')
    expect(updated.name).toBe('New')
  })

  it('regenerates join code', async () => {
    const o = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'OLDXXX' })
    const updated = await leagues.updateJoinCode(l.id, 'NEWYYY')
    expect(updated.joinCode).toBe('NEWYYY')
  })

  it('deletes league (cascades members)', async () => {
    const o = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'DEL001' })
    await leagues.deleteById(l.id)
    expect(await leagues.findByJoinCode('DEL001')).toBeNull()
  })

  it('adds a member to a league', async () => {
    const o = await makeUser('o@x.com')
    const u = await makeUser('m@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'ADD001' })
    await members.add(l.id, u.id)
    const list = await members.listByLeague(l.id)
    expect(list.map((x) => x.userId).sort()).toEqual([o.id, u.id].sort())
  })

  it('rejects duplicate membership', async () => {
    const o = await makeUser('o2@x.com')
    const u = await makeUser('m2@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'DUP001' })
    await members.add(l.id, u.id)
    await expect(members.add(l.id, u.id)).rejects.toThrow(/duplicate|unique|key/i)
  })

  it('lists leagues for a user with role', async () => {
    const owner = await makeUser('owner@x.com')
    const joiner = await makeUser('joiner@x.com')
    const l1 = await leagues.createLeagueWithOwner({ name: 'L1', ownerUserId: owner.id, joinCode: 'ROL001' })
    const l2 = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: joiner.id, joinCode: 'ROL002' })
    await members.add(l1.id, joiner.id)
    const list = await leagues.listForUser(joiner.id)
    const byId = new Map(list.map((x) => [x.id, x.role]))
    expect(byId.get(l1.id)).toBe('member')
    expect(byId.get(l2.id)).toBe('owner')
  })

  it('removes a member', async () => {
    const o = await makeUser('rm-o@x.com')
    const u = await makeUser('rm-u@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'RMV001' })
    await members.add(l.id, u.id)
    await members.remove(l.id, u.id)
    const list = await members.listByLeague(l.id)
    expect(list.map((x) => x.userId)).not.toContain(u.id)
  })

  it('checks membership', async () => {
    const o = await makeUser('chk-o@x.com')
    const u = await makeUser('chk-u@x.com')
    const stranger = await makeUser('chk-s@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'CHK001' })
    await members.add(l.id, u.id)
    expect(await members.isMember(l.id, u.id)).toBe(true)
    expect(await members.isMember(l.id, stranger.id)).toBe(false)
  })
})
