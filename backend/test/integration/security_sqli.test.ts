import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import { getDb } from '../../src/db/client.js'
import { sql } from 'drizzle-orm'

/// SQL-injection regression suite. The backend's only query paths are Drizzle
/// query-builder calls and drizzle `sql` tagged templates — both bind every
/// interpolation as a parameter. These tests push classic injection payloads
/// through the public write paths and assert (a) the payload lands verbatim
/// as data, (b) the tables it tries to drop/delete still exist.

const INJ = [
  `x'); DROP TABLE score;--`,
  `Robert'; DELETE FROM prediction WHERE '1'='1`,
  `" OR ""="`,
  `1; SELECT pg_sleep(0)`
]

async function newApp() {
  return buildApp({ scheduler: null } as any)
}

async function tableCount(name: 'score' | 'prediction' | 'user' | 'league'): Promise<number> {
  const db = getDb()
  // sql.raw is safe here: `name` is a compile-time literal from the union type.
  const res = await db.execute(sql.raw(`SELECT count(*)::int AS n FROM "${name}"`))
  return (res as unknown as { rows: { n: number }[] }).rows[0]!.n
}

describe('SQL injection resistance', () => {
  it('stores hostile display names verbatim; tables survive', async () => {
    const app = await newApp()
    for (const [i, payload] of INJ.entries()) {
      const r = await app.inject({
        method: 'POST', url: '/api/auth/signup',
        payload: {
          email: `inj-${i}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@x.com`,
          password: 'hunter22',
          displayName: payload.slice(0, 40)
        }
      })
      expect(r.statusCode).toBeLessThan(500)
      if (r.statusCode === 200 || r.statusCode === 201) {
        expect(r.json().user.displayName).toBe(payload.slice(0, 40))
      }
    }
    expect(await tableCount('score')).toBeGreaterThanOrEqual(0)
    expect(await tableCount('prediction')).toBeGreaterThanOrEqual(0)
    await app.close()
  })

  it('hostile league names and join codes are inert', async () => {
    const app = await newApp()
    const s = await app.inject({
      method: 'POST', url: '/api/auth/signup',
      payload: { email: `inj-lg-${Date.now()}@x.com`, password: 'hunter22', displayName: 'inj-league-owner' }
    })
    const token = s.json().token as string
    const lc = await app.inject({
      method: 'POST', url: '/api/leagues',
      headers: { authorization: `Bearer ${token}` },
      payload: { name: `L'); DROP TABLE league;--` }
    })
    expect(lc.statusCode).toBeLessThan(500)
    const join = await app.inject({
      method: 'POST', url: '/api/leagues/join',
      headers: { authorization: `Bearer ${token}` },
      payload: { joinCode: `' OR '1'='1` }
    })
    expect([400, 401, 404]).toContain(join.statusCode)
    expect(await tableCount('league')).toBeGreaterThanOrEqual(1)
    await app.close()
  })

  it('hostile driver codes in an import are skipped as unknown, not executed', async () => {
    const app = await newApp()
    await seasons.upsertSeason({ year: 2031, isCurrent: false })
    const s = await app.inject({
      method: 'POST', url: '/api/auth/signup',
      payload: { email: `inj-im-${Date.now()}@x.com`, password: 'hunter22', displayName: 'inj-importer' }
    })
    const token = s.json().token as string
    const userId = s.json().user.id as string
    const lc = await app.inject({
      method: 'POST', url: '/api/leagues',
      headers: { authorization: `Bearer ${token}` }, payload: { name: 'InjTestL' }
    })
    const leagueId = lc.json().league.id as string
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: { authorization: `Bearer ${token}` },
      payload: {
        schemaVersion: 1,
        league: { id: leagueId, name: 'InjTestL' },
        seasonYear: 2031,
        overwrite: false,
        predictions: [{
          userId, sessionId: 999999,
          picks: [{ position: 1, driverCode: `VER'; DROP TABLE prediction;--` }]
        }]
      }
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().plan).toHaveLength(0)
    expect(await tableCount('prediction')).toBeGreaterThanOrEqual(0)
    await app.close()
  })

  it('malformed UUIDs in the URL do not reach the database as SQL', async () => {
    const app = await newApp()
    const s = await app.inject({
      method: 'POST', url: '/api/auth/signup',
      payload: { email: `inj-uuid-${Date.now()}@x.com`, password: 'hunter22', displayName: 'inj-uuid' }
    })
    const token = s.json().token as string
    const r = await app.inject({
      method: 'GET', url: `/api/leagues/${encodeURIComponent(`1' OR '1'='1`)}/imports`,
      headers: { authorization: `Bearer ${token}` }
    })
    // Parameterized uuid comparison → invalid-uuid error surfaces as a client
    // error, never as executed SQL.
    expect(r.statusCode).toBeGreaterThanOrEqual(400)
    expect(await tableCount('user')).toBeGreaterThanOrEqual(1)
    await app.close()
  })
})
