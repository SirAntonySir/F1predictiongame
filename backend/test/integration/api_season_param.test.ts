import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'

const driver = (code: string) => ({ code, givenName: code, familyName: code, nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
const ctor = (id: string) => ({ id, name: id, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })

describe('season query param on read routes', () => {
  beforeEach(async () => {
    await seasons.upsertSeason({ year: 2025, isCurrent: false })
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    await drivers.upsertDriver(driver('NOR'))
    await drivers.upsertDriver(driver('VER'))
    await constructors.upsertConstructor(ctor('mclaren'))
    await constructors.upsertConstructor(ctor('red_bull'))
    // 2025 leader = NOR, 2026 leader = VER
    await standings.replaceDriverStandings(2025, [{ seasonYear: 2025, driverCode: 'NOR', position: 1, points: 400, wins: 10, constructorId: 'mclaren' }])
    await standings.replaceDriverStandings(2026, [{ seasonYear: 2026, driverCode: 'VER', position: 1, points: 300, wins: 8, constructorId: 'red_bull' }])
  })

  it('GET /api/standings/drivers defaults to the current season (2026)', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/standings/drivers' })
    expect(res.statusCode).toBe(200)
    expect(res.json()[0].driverCode).toBe('VER')
    await app.close()
  })

  it('GET /api/standings/drivers?season=2025 returns the 2025 standings', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/standings/drivers?season=2025' })
    expect(res.statusCode).toBe(200)
    expect(res.json()[0].driverCode).toBe('NOR')
    await app.close()
  })

  it('GET /api/standings/drivers?season=abc is a 400', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/standings/drivers?season=abc' })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('GET /api/seasons lists all seasons, newest first', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/seasons' })
    expect(res.statusCode).toBe(200)
    expect(res.json().map((s: { year: number }) => s.year)).toEqual([2026, 2025])
    await app.close()
  })
})
