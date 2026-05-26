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
import * as results from '../../src/repo/results.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedSprintQualiSession() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 2, name: 'Chinese GP', circuitName: 'Shanghai',
    country: 'China', hasSprint: true
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
    eventId: ev.id, type: 'sprint_quali',
    scheduledStart: past, scheduledEnd: past,
    status: 'scheduled', openf1SessionKey: 11236
  })
}

describe('Crawler — sprint_quali via OpenF1', () => {
  it('writes a finished session_result for a sprint_quali session', async () => {
    const ses = await seedSprintQualiSession()

    const jolpica = new JolpicaClient(
      'https://example.invalid',
      staticFetch((url) => {
        if (url.includes('Standings')) return { status: 404, body: {} }
        return { status: 200, body: { MRData: { RaceTable: { Races: [] } } } }
      })
    )
    const wiki = new WikipediaClient(
      'https://example.invalid',
      staticFetch(() => ({ status: 200, body: { query: { pages: {} } } }))
    )
    const openf1 = new OpenF1Client(
      'https://api.openf1.org/v1',
      staticFetch((url) => {
        if (url.endsWith('/session_result?session_key=11236')) {
          return { status: 200, body: [
            { position: 1, driver_number: 4, duration: [79.5, 78.9, 78.5],
              gap_to_leader: [0, 0, 0], dnf: false, dns: false, dsq: false,
              number_of_laps: 19, meeting_key: 1280, session_key: 11236 }
          ] }
        }
        if (url.endsWith('/drivers?session_key=11236')) {
          return { status: 200, body: [
            { driver_number: 4, name_acronym: 'NOR', first_name: 'Lando',
              last_name: 'Norris', team_name: 'McLaren',
              headshot_url: 'https://example.com/nor.png', team_colour: 'F47600' }
          ] }
        }
        return { status: 200, body: [] }
      })
    )

    const summary = await runTick(jolpica, wiki, openf1)
    expect(summary.sessionsFinished).toBe(1)
    expect(summary.errors).toBe(0)

    const refreshed = await sessions.getById(ses.id!)
    expect(refreshed?.status).toBe('finished')

    const rows = await results.listForSession(ses.id!)
    expect(rows.length).toBe(1)
    expect(rows[0].driverCode).toBe('NOR')
    expect(rows[0].q1).toBe('1:19.500')
    expect(rows[0].q2).toBe('1:18.900')
    expect(rows[0].q3).toBe('1:18.500')
    expect(rows[0].raceTime).toBeNull()
  })

  it('skips a sprint_quali session when its openf1SessionKey is null', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2026, round: 2, name: 'Chinese GP', circuitName: 'Shanghai',
      country: 'China', hasSprint: true
    })
    const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali',
      scheduledStart: past, scheduledEnd: past,
      status: 'scheduled', openf1SessionKey: null
    })

    const jolpica = new JolpicaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { MRData: { RaceTable: { Races: [] } } } })))
    const wiki = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))
    const openf1 = new OpenF1Client('https://api.openf1.org/v1', staticFetch(() => ({ status: 200, body: [] })))

    const summary = await runTick(jolpica, wiki, openf1)
    expect(summary.sessionsFinished).toBe(0)
    expect(summary.sessionsSkipped).toBe(1)
  })
})
