import { describe, it, expect, vi } from 'vitest'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedRaceSession(openf1Key: number | null = 9001) {
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
    status: 'scheduled', openf1SessionKey: openf1Key
  })
}

function jolpicaRace(rows: Array<{ position: number; code: string }>) {
  const body = {
    MRData: { RaceTable: { Races: [{ Results: rows.map((r) => ({
      position: String(r.position),
      Driver: { code: r.code, driverId: r.code.toLowerCase(), givenName: r.code, familyName: r.code, url: null, nationality: 'Dutch', permanentNumber: '1' },
      Constructor: { constructorId: 'red_bull', name: 'Red Bull', url: null, nationality: 'Austrian' }
    })) }] } }
  }
  return new JolpicaClient('https://example.invalid', staticFetch(() => ({ status: 200, body })))
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

describe('Crawler — OpenF1 cross-check', () => {
  it('persists Jolpica and logs no warning when classifications match', async () => {
    const ses = await seedRaceSession()
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER'])
    expect(warn).not.toHaveBeenCalled()
    warn.mockRestore()
  })

  it('persists Jolpica and logs exactly one warning on mismatch', async () => {
    const ses = await seedRaceSession()
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1Race([{ position: 1, code: 'PER' }, { position: 2, code: 'VER' }])
    )
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER']) // Jolpica wins
    expect(warn).toHaveBeenCalledTimes(1)
    warn.mockRestore()
  })

  it('falls back to OpenF1 rows when Jolpica returns empty', async () => {
    const ses = await seedRaceSession()
    const jolpicaEmpty = new JolpicaClient(
      'https://example.invalid',
      staticFetch(() => ({ status: 200, body: { MRData: { RaceTable: { Races: [] } } } }))
    )
    await runTick(
      jolpicaEmpty,
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER'])
  })

  it('does not invoke OpenF1 when openf1SessionKey is null (no cross-check)', async () => {
    const ses = await seedRaceSession(null)
    let openf1Calls = 0
    const openf1 = new OpenF1Client('https://api.openf1.org/v1', (async (url: string | URL) => {
      openf1Calls++
      return new Response('[]', { status: 200 })
    }) as unknown as typeof fetch)

    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1
    )
    expect(openf1Calls).toBe(0)
    const rows = await results.listForSession(ses.id!)
    expect(rows.length).toBe(2)
  })
})
