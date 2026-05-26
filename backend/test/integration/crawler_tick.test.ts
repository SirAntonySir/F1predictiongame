import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as standings from '../../src/repo/standings.js'
import * as drivers from '../../src/repo/drivers.js'

function jolpicaFetch(routeMap: Record<string, string | number>) {
  // routeMap: url substring -> fixture filename OR HTTP status code for empty body
  return async (req: string | URL | Request) => {
    const url = typeof req === 'string' ? req : req.toString()
    for (const [needle, target] of Object.entries(routeMap)) {
      if (url.includes(needle)) {
        if (typeof target === 'number') return new Response('', { status: target })
        const body = readFileSync(resolve('test/fixtures/jolpica', target), 'utf8')
        return new Response(body, { status: 200 })
      }
    }
    return new Response('not in routeMap: ' + url, { status: 404 })
  }
}

async function seed2024Round1Past() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000)
  await sessions.upsertSession({
    eventId: ev.id, type: 'race', scheduledStart: yesterday, scheduledEnd: yesterday, status: 'scheduled',
  openf1SessionKey: null
  })
  await sessions.upsertSession({
    eventId: ev.id, type: 'qualifying', scheduledStart: yesterday, scheduledEnd: yesterday, status: 'scheduled',
  openf1SessionKey: null
  })
  return ev
}

describe('runTick', () => {
  it('fetches race + qualifying results, marks finished, refreshes standings', async () => {
    await seed2024Round1Past()
    const jolpica = new JolpicaClient('https://x', jolpicaFetch({
      '/2024/1/results.json': 'race-2024-1.json',
      '/2024/1/qualifying.json': 'qualifying-2024-1.json',
      '/driverStandings.json': 'driver-standings-2024.json',
      '/constructorStandings.json': 'constructor-standings-2024.json'
    }))
    const wiki = new WikipediaClient('https://x', async () => new Response(JSON.stringify({
      query: { pages: { '1': { thumbnail: { source: 'https://img.test/x.png' } } } }
    }), { status: 200 }))

    const summary = await runTick(jolpica, wiki)
    expect(summary.sessionsFinished).toBeGreaterThanOrEqual(2)

    const candidates = await sessions.listCandidates()
    expect(candidates).toEqual([])

    const drivList = await standings.listDriverStandings(2024)
    expect(drivList.length).toBeGreaterThan(15)
  })

  it('skips a sprint_quali session whose endpoint returns 404 and leaves it scheduled', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2024, round: 5, name: 'China', circuitName: 'SIC', country: 'China', hasSprint: true
    })
    const past = new Date(Date.now() - 2 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali', scheduledStart: past, scheduledEnd: past, status: 'scheduled',
    openf1SessionKey: null
    })

    const jolpica = new JolpicaClient('https://x', jolpicaFetch({
      '/sprintQualifying.json': 404
    }))
    const wiki = new WikipediaClient('https://x', async () => new Response('{}', { status: 200 }))

    const summary = await runTick(jolpica, wiki)
    expect(summary.sessionsFinished).toBe(0)
    expect((await sessions.listCandidates()).length).toBeGreaterThan(0)
  })

  it('enriches Wikipedia images on first-seen drivers/constructors only', async () => {
    await seed2024Round1Past()
    let calls = 0
    const wiki = new WikipediaClient('https://x', async () => {
      calls++
      return new Response(JSON.stringify({ query: { pages: { '1': { thumbnail: { source: 'https://img/x' } } } } }), { status: 200 })
    })
    const jolpica = new JolpicaClient('https://x', jolpicaFetch({
      '/2024/1/results.json': 'race-2024-1.json',
      '/2024/1/qualifying.json': 'qualifying-2024-1.json',
      '/driverStandings.json': 'driver-standings-2024.json',
      '/constructorStandings.json': 'constructor-standings-2024.json'
    }))

    await runTick(jolpica, wiki)
    const callsAfterFirst = calls
    expect(callsAfterFirst).toBeGreaterThan(0)
    // Second tick: no candidates (all sessions finished) -> no further wiki calls.
    // This indirectly verifies that already-known entities are not re-enriched.
    await runTick(jolpica, wiki)
    expect(calls).toBe(callsAfterFirst)
  })

  it('upserts driver/constructor lookup rows with wikipedia URLs from results', async () => {
    await seed2024Round1Past()
    const jolpica = new JolpicaClient('https://x', jolpicaFetch({
      '/2024/1/results.json': 'race-2024-1.json',
      '/2024/1/qualifying.json': 'qualifying-2024-1.json',
      '/driverStandings.json': 'driver-standings-2024.json',
      '/constructorStandings.json': 'constructor-standings-2024.json'
    }))
    const wiki = new WikipediaClient('https://x', async () => new Response('{}', { status: 200 }))

    await runTick(jolpica, wiki)
    const ver = await drivers.getByCode('VER')
    expect(ver).toBeTruthy()
    expect(ver?.wikipediaUrl).toContain('wikipedia.org')
  })
})
