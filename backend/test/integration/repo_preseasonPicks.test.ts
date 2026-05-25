import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as picks from '../../src/repo/preseasonPicks.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'Max', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  return await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
}

describe('preseasonPicks repo', () => {
  it('upserts and reads a pick back', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'VER', constructorId: 'red_bull' })
    const got = await picks.getPick(u.id, 2026, 'surprise')
    expect(got?.driverCode).toBe('VER')
    expect(got?.constructorId).toBe('red_bull')
  })

  it('upsert replaces existing values', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: 'VER', constructorId: null })
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: null, constructorId: 'red_bull' })
    const got = await picks.getPick(u.id, 2026, 'dnf')
    expect(got?.driverCode).toBeNull()
    expect(got?.constructorId).toBe('red_bull')
  })

  it('accepts driver-only and team-only picks (nullable columns)', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'poles', { driverCode: 'VER', constructorId: null })
    const got = await picks.getPick(u.id, 2026, 'poles')
    expect(got?.driverCode).toBe('VER')
    expect(got?.constructorId).toBeNull()
  })

  it('listForUser returns all picks for a season', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'VER', constructorId: null })
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: null, constructorId: 'red_bull' })
    const all = await picks.listForUser(u.id, 2026)
    expect(all).toHaveLength(2)
  })

  it('deletePick removes the row', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'fastest_lap', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.deletePick(u.id, 2026, 'fastest_lap')
    expect(await picks.getPick(u.id, 2026, 'fastest_lap')).toBeNull()
  })

  it('cascades from user delete', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    await users.deleteById(u.id)
    expect(await picks.getPick(u.id, 2026, 'wdc_wcc')).toBeNull()
  })
})
