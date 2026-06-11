import { describe, it, expect } from 'vitest'
import { runBootstrap } from '../../src/crawler/bootstrap.js'
import { Scheduler } from '../../src/crawler/scheduler.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'

// Minimal Ergast-shaped schedule for an arbitrary year (race sessions only).
function makeSchedule(year: number, rounds = 3) {
  return {
    MRData: { RaceTable: { season: String(year), Races: Array.from({ length: rounds }, (_, i) => ({
      round: String(i + 1),
      raceName: `Round ${i + 1} Grand Prix`,
      Circuit: { circuitName: `Circuit ${i + 1}`, Location: { country: 'Testland' } },
      date: `${year}-0${i + 3}-15`, time: '13:00:00Z'
    })) } }
  }
}
// Serve a schedule for years in `published`; everything else (results/standings) 404 -> null.
function jolpicaFor(published: Set<number>) {
  return async (url: string | URL | Request) => {
    const m = String(url).match(/\/f1\/(\d{4})\.json$/)
    if (m && published.has(Number(m[1]))) {
      return new Response(JSON.stringify(makeSchedule(Number(m[1]))), { status: 200 })
    }
    return new Response('not found', { status: 404 })
  }
}
const no = async () => new Response('x', { status: 404 })
const fakeOpenF1 = () => new OpenF1Client('https://x', no)
const fakeWiki = () => new WikipediaClient('https://x', no)

describe('season rollover', () => {
  it('runBootstrap with {isCurrent:false} loads the season but does NOT steal current', async () => {
    await seasons.upsertSeason({ year: 2099, isCurrent: true }) // dummy active season
    const jolpica = new JolpicaClient('https://x', jolpicaFor(new Set([2030])))
    await runBootstrap(jolpica, 2030, fakeOpenF1(), { isCurrent: false })

    expect(await seasons.getCurrent()).toMatchObject({ year: 2099, isCurrent: true })
    expect((await seasons.list()).find((s) => s.year === 2030)).toMatchObject({ year: 2030, isCurrent: false })
    expect((await events.listForSeason(2030)).length).toBe(3)
  })

  it('weekly job pre-loads NEXT year (non-current) once its schedule is published', async () => {
    await seasons.upsertSeason({ year: 2030, isCurrent: true })
    // 2030 (current) + 2031 (next) both have published schedules.
    const jolpica = new JolpicaClient('https://x', jolpicaFor(new Set([2030, 2031])))
    const sched = new Scheduler(jolpica, fakeWiki(), fakeOpenF1())
    await sched.weeklyOnce()

    expect(await seasons.getCurrent()).toMatchObject({ year: 2030 }) // still current
    expect((await seasons.list()).find((s) => s.year === 2031)).toMatchObject({ year: 2031, isCurrent: false })
    expect((await events.listForSeason(2031)).length).toBe(3) // 2031 calendar loaded
  })

  it('weekly job does nothing extra when next year is not yet published', async () => {
    await seasons.upsertSeason({ year: 2030, isCurrent: true })
    const jolpica = new JolpicaClient('https://x', jolpicaFor(new Set([2030]))) // 2031 -> 404
    const sched = new Scheduler(jolpica, fakeWiki(), fakeOpenF1())
    await sched.weeklyOnce()
    expect((await seasons.list()).some((s) => s.year === 2031)).toBe(false)
  })

  it('POST /admin/seasons/:year/activate flips is_current to a loaded season', async () => {
    await seasons.upsertSeason({ year: 2030, isCurrent: true })
    await seasons.upsertSeason({ year: 2031, isCurrent: false })
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({
      method: 'POST', url: '/admin/seasons/2031/activate',
      headers: { 'x-admin-token': process.env.ADMIN_TOKEN! }
    })
    expect(res.statusCode).toBe(200)
    expect(await seasons.getCurrent()).toMatchObject({ year: 2031, isCurrent: true })
    expect((await seasons.list()).find((s) => s.year === 2030)).toMatchObject({ isCurrent: false })

    // a season that hasn't been loaded yet -> 404
    const miss = await app.inject({
      method: 'POST', url: '/admin/seasons/9999/activate',
      headers: { 'x-admin-token': process.env.ADMIN_TOKEN! }
    })
    expect(miss.statusCode).toBe(404)
    await app.close()
  })
})
