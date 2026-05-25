import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/preseasonStandings.js'

async function seedDriversAndUser() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  for (const code of ['VER', 'PER', 'HAM', 'RUS', 'NOR']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  return await users.insertUser({ email: 's@x.com', passwordHash: 'h', displayName: 'S' })
}

describe('preseasonStandings repo', () => {
  it('replaces driver picks atomically', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'HAM' }
    ])
    let list = await standings.listDriverPicks(u.id, 2026)
    expect(list).toEqual([
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'HAM' }
    ])

    await standings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'HAM' }
    ])
    list = await standings.listDriverPicks(u.id, 2026)
    expect(list).toEqual([{ position: 1, entityId: 'HAM' }])
  })

  it('rejects duplicate driver within a season for the same user', async () => {
    const u = await seedDriversAndUser()
    await expect(standings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'VER' }
    ])).rejects.toThrow(/duplicate|unique/i)
  })

  it('replaces constructor picks', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceConstructorPicks(u.id, 2026, [
      { position: 1, entityId: 'red_bull' },
      { position: 2, entityId: 'mercedes' }
    ])
    const list = await standings.listConstructorPicks(u.id, 2026)
    expect(list).toEqual([
      { position: 1, entityId: 'red_bull' },
      { position: 2, entityId: 'mercedes' }
    ])
  })

  it('empty replace clears the picks', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceDriverPicks(u.id, 2026, [{ position: 1, entityId: 'VER' }])
    await standings.replaceDriverPicks(u.id, 2026, [])
    expect(await standings.listDriverPicks(u.id, 2026)).toEqual([])
  })

  it('cascades from user delete', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceDriverPicks(u.id, 2026, [{ position: 1, entityId: 'VER' }])
    await users.deleteById(u.id)
    expect(await standings.listDriverPicks(u.id, 2026)).toEqual([])
  })
})
