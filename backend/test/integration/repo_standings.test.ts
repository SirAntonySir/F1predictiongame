import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'

describe('standings repo', () => {
  it('overwrites driver standings on each refresh', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    await drivers.upsertDriver({ code: 'VER', givenName: 'Max', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await drivers.upsertDriver({ code: 'HAM', givenName: 'Lewis', familyName: 'H', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'RB', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await constructors.upsertConstructor({ id: 'mercedes', name: 'Merc', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })

    await standings.replaceDriverStandings(2024, [
      { seasonYear: 2024, driverCode: 'VER', position: 1, points: 25, wins: 1, constructorId: 'red_bull' },
      { seasonYear: 2024, driverCode: 'HAM', position: 2, points: 18, wins: 0, constructorId: 'mercedes' }
    ])
    expect((await standings.listDriverStandings(2024)).length).toBe(2)

    await standings.replaceDriverStandings(2024, [
      { seasonYear: 2024, driverCode: 'VER', position: 1, points: 50, wins: 2, constructorId: 'red_bull' }
    ])
    const rows = await standings.listDriverStandings(2024)
    expect(rows.length).toBe(1)
    expect(rows[0]!.points).toBe(50)
  })

  it('overwrites constructor standings on each refresh', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'RB', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await standings.replaceConstructorStandings(2024, [
      { seasonYear: 2024, constructorId: 'red_bull', position: 1, points: 100, wins: 5 }
    ])
    expect((await standings.listConstructorStandings(2024))[0]!.points).toBe(100)
  })

  it('listDriverStandings returns rows ordered by position', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    await drivers.upsertDriver({ code: 'A', givenName: 'A', familyName: 'A', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await drivers.upsertDriver({ code: 'B', givenName: 'B', familyName: 'B', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await constructors.upsertConstructor({ id: 'c1', name: 'C1', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await standings.replaceDriverStandings(2024, [
      { seasonYear: 2024, driverCode: 'B', position: 2, points: 18, wins: 0, constructorId: 'c1' },
      { seasonYear: 2024, driverCode: 'A', position: 1, points: 25, wins: 1, constructorId: 'c1' }
    ])
    const rows = await standings.listDriverStandings(2024)
    expect(rows.map((r) => r.driverCode)).toEqual(['A', 'B'])
  })
})
