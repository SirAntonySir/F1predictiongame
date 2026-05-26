import { describe, it, expect } from 'vitest'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedNorWithoutHeadshot() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
  await drivers.upsertDriver({
    code: 'NOR', givenName: 'Lando', familyName: 'Norris',
    nationality: null, permanentNumber: 4, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  await constructors.upsertConstructor({
    id: 'mclaren', name: 'McLaren', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: past, scheduledEnd: past,
    status: 'scheduled', openf1SessionKey: 9001
  })
}

function jolpicaRace(code: string, ctor: string) {
  const body = {
    MRData: { RaceTable: { Races: [{ Results: [{
      position: '1',
      Driver: { code, driverId: code.toLowerCase(), givenName: 'X', familyName: 'X', url: null, nationality: 'X', permanentNumber: '4' },
      Constructor: { constructorId: ctor, name: ctor, url: null, nationality: 'X' }
    }] }] } }
  }
  return new JolpicaClient('https://example.invalid', staticFetch(() => ({ status: 200, body })))
}

function openf1WithDriver() {
  return new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
    if (url.endsWith('/session_result?session_key=9001')) {
      return { status: 200, body: [{ position: 1, driver_number: 4, duration: [],
        gap_to_leader: [], dnf: false, dns: false, dsq: false, number_of_laps: 1,
        meeting_key: 1, session_key: 9001 }] }
    }
    if (url.endsWith('/drivers?session_key=9001')) {
      return { status: 200, body: [{ driver_number: 4, name_acronym: 'NOR',
        first_name: 'Lando', last_name: 'Norris', team_name: 'McLaren',
        headshot_url: 'https://example.com/nor.png', team_colour: 'F47600' }] }
    }
    return { status: 200, body: [] }
  }))
}

const wikiNoop = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))

describe('Crawler — OpenF1 driver/team enrichment', () => {
  it('writes headshot_url for a driver with no headshot', async () => {
    await seedNorWithoutHeadshot()
    await runTick(jolpicaRace('NOR', 'mclaren'), wikiNoop, openf1WithDriver())
    const d = await drivers.getByCode('NOR')
    expect(d?.headshotUrl).toBe('https://example.com/nor.png')
  })

  it('writes team_colour for a constructor with no colour', async () => {
    await seedNorWithoutHeadshot()
    await runTick(jolpicaRace('NOR', 'mclaren'), wikiNoop, openf1WithDriver())
    const c = await constructors.getById('mclaren')
    expect(c?.teamColour).toBe('F47600')
  })

  it('does not overwrite an existing non-null headshot_url', async () => {
    await seedNorWithoutHeadshot()
    await drivers.setHeadshotUrl('NOR', 'https://manual.example/keep.png')
    await runTick(jolpicaRace('NOR', 'mclaren'), wikiNoop, openf1WithDriver())
    const d = await drivers.getByCode('NOR')
    expect(d?.headshotUrl).toBe('https://manual.example/keep.png')
  })
})
