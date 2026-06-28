import { describe, it, expect } from 'vitest'
import { runTick } from '../../src/crawler/tick.js'
import { reconcileOnce } from '../../src/crawler/reconcile.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'
import * as standings from '../../src/repo/standings.js'
import { getDb } from '../../src/db/client.js'
import { sql } from 'drizzle-orm'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedRaceSession() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain GP', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
  for (const code of ['VER', 'PER']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: code, nationality: null,
      permanentNumber: 1, wikipediaUrl: null, imageUrl: null,
      imageUrlOverride: null, headshotUrl: null
    })
  }
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: past, scheduledEnd: past,
    status: 'scheduled', openf1SessionKey: 9001
  })
}

function driverStandingsBody(rows: Array<{ position: number; code: string }>) {
  return { MRData: { StandingsTable: { season: '2024', StandingsLists: [{ DriverStandings: rows.map((r) => ({
    position: String(r.position), points: String(100 - r.position), wins: r.position === 1 ? '1' : '0',
    Driver: { code: r.code, driverId: r.code.toLowerCase(), givenName: r.code, familyName: r.code, url: null, nationality: 'Dutch', permanentNumber: '1' },
    Constructors: [{ constructorId: 'red_bull', name: 'Red Bull', url: null, nationality: 'Austrian' }]
  })) }] } } }
}

function constructorStandingsBody() {
  return { MRData: { StandingsTable: { season: '2024', StandingsLists: [{ ConstructorStandings: [{
    position: '1', points: '200', wins: '1',
    Constructor: { constructorId: 'red_bull', name: 'Red Bull', url: null, nationality: 'Austrian' }
  }] }] } } }
}

function jolpicaRace(rows: Array<{ position: number; code: string }>) {
  const body = {
    MRData: { RaceTable: { Races: [{ Results: rows.map((r) => ({
      position: String(r.position),
      Driver: { code: r.code, driverId: r.code.toLowerCase(), givenName: r.code, familyName: r.code, url: null, nationality: 'Dutch', permanentNumber: '1' },
      Constructor: { constructorId: 'red_bull', name: 'Red Bull', url: null, nationality: 'Austrian' }
    })) }] } }
  }
  return new JolpicaClient('https://example.invalid', staticFetch((url) => {
    if (url.includes('/driverStandings.json')) return { status: 200, body: driverStandingsBody(rows) }
    if (url.includes('/constructorStandings.json')) return { status: 200, body: constructorStandingsBody() }
    return { status: 200, body }
  }))
}

function jolpicaEmpty() {
  return new JolpicaClient('https://example.invalid', staticFetch((url) => {
    if (url.includes('/driverStandings.json')) return { status: 200, body: { MRData: { StandingsTable: { season: '2024', StandingsLists: [] } } } }
    if (url.includes('/constructorStandings.json')) return { status: 200, body: { MRData: { StandingsTable: { season: '2024', StandingsLists: [] } } } }
    return { status: 200, body: { MRData: { RaceTable: { Races: [] } } } }
  }))
}

function openf1Race(rows: Array<{ position: number; code: string }>) {
  return new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
    if (url.endsWith('/session_result?session_key=9001')) {
      return { status: 200, body: rows.map((r) => ({
        position: r.position, driver_number: r.code === 'VER' ? 1 : 11,
        duration: [], gap_to_leader: [], dnf: false, dns: false, dsq: false,
        number_of_laps: 1, meeting_key: 1, session_key: 9001
      })) }
    }
    if (url.endsWith('/drivers?session_key=9001')) {
      return { status: 200, body: [
        { driver_number: 1, name_acronym: 'VER', first_name: 'Max', last_name: 'Verstappen', team_name: 'Red Bull', headshot_url: null, team_colour: null },
        { driver_number: 11, name_acronym: 'PER', first_name: 'Sergio', last_name: 'Pérez', team_name: 'Red Bull', headshot_url: null, team_colour: null }
      ] }
    }
    return { status: 200, body: [] }
  }))
}

const wikiNoop = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))

async function sourceOf(sessionId: number): Promise<string> {
  const db = getDb()
  const rows = await db.execute(sql`SELECT source FROM session_result WHERE session_id = ${sessionId} LIMIT 1`)
  return ((rows as unknown as { rows: { source: string }[] }).rows[0]?.source) ?? 'unknown'
}

async function lastReconciledAtOf(sessionId: number): Promise<Date | null> {
  const db = getDb()
  const rows = await db.execute(sql`SELECT last_reconciled_at FROM session WHERE id = ${sessionId}`)
  const v = (rows as unknown as { rows: { last_reconciled_at: string | null }[] }).rows[0]?.last_reconciled_at
  return v ? new Date(v) : null
}

describe('reconcileOnce', () => {
  it('stamps last_reconciled_at when OpenF1 and Jolpica agree (no row swap)', async () => {
    const ses = await seedRaceSession()
    await runTick(
      jolpicaEmpty(),
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    expect(await sourceOf(ses.id!)).toBe('openf1')

    const summary = await reconcileOnce(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop
    )
    expect(summary.attempted).toBe(1)
    expect(summary.matched).toBe(1)
    expect(summary.replaced).toBe(0)
    expect(await lastReconciledAtOf(ses.id!)).not.toBeNull()
    // Row order unchanged.
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER'])
  })

  it('replaces rows + flips source to jolpica when classifications diverge (post-stewards penalty)', async () => {
    const ses = await seedRaceSession()
    // OpenF1 reports the on-track order: VER 1st, PER 2nd.
    await runTick(
      jolpicaEmpty(),
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    expect(await sourceOf(ses.id!)).toBe('openf1')

    // Jolpica publishes the official classification: VER got a 10s penalty,
    // PER inherits the win. The reconciler should swap and rescore.
    const summary = await reconcileOnce(
      jolpicaRace([{ position: 1, code: 'PER' }, { position: 2, code: 'VER' }]),
      wikiNoop
    )
    expect(summary.attempted).toBe(1)
    expect(summary.replaced).toBe(1)
    expect(summary.matched).toBe(0)
    expect(await sourceOf(ses.id!)).toBe('jolpica')
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['PER', 'VER'])
  })

  it('does not touch jolpica-sourced sessions (they are already official)', async () => {
    const ses = await seedRaceSession()
    // Drive the tick down the Jolpica fallback path (OpenF1 returns nothing).
    const openf1Empty = new OpenF1Client('https://api.openf1.org/v1', staticFetch(() => ({ status: 200, body: [] })))
    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1Empty
    )
    expect(await sourceOf(ses.id!)).toBe('jolpica')

    const summary = await reconcileOnce(jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]), wikiNoop)
    expect(summary.attempted).toBe(0)
  })

  it('records noJolpicaData when Jolpica is still empty — leaves the session for the next pass', async () => {
    const ses = await seedRaceSession()
    await runTick(
      jolpicaEmpty(),
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )

    const summary = await reconcileOnce(jolpicaEmpty(), wikiNoop)
    expect(summary.attempted).toBe(1)
    expect(summary.noJolpicaData).toBe(1)
    expect(await lastReconciledAtOf(ses.id!)).toBeNull()
    expect(await sourceOf(ses.id!)).toBe('openf1')
  })

  it('refreshes season standings as a catch-up whenever there is reconcilable activity', async () => {
    await seedRaceSession()
    // OpenF1 fast path finished the session; the finish-tick standings refresh
    // never ran because the tick used jolpicaEmpty (no standings yet).
    await runTick(
      jolpicaEmpty(),
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    expect(await standings.listDriverStandings(2024)).toHaveLength(0)

    // Reconcile pass now has Jolpica standings — it should pull them in even
    // when the session classification itself matches (no row swap needed).
    const summary = await reconcileOnce(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop
    )
    expect(summary.standingsRefreshed).toBe(true)
    const drv = await standings.listDriverStandings(2024)
    expect(drv.map((s) => s.driverCode)).toEqual(['VER', 'PER'])
    expect(await standings.listConstructorStandings(2024)).toHaveLength(1)
  })

  it('does not refresh standings when there is nothing to reconcile', async () => {
    // No reconcilable sessions → no catch-up, standings left untouched.
    const summary = await reconcileOnce(jolpicaEmpty(), wikiNoop)
    expect(summary.attempted).toBe(0)
    expect(summary.standingsRefreshed).toBe(false)
  })
})
