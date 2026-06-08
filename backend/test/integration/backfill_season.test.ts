import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { backfillSeasonData } from '../../src/scripts/backfillSeasonData.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'

// Schedule fetch returns the 2024 fixture for the schedule URL; every other URL
// (results, standings) 404s -> client returns null -> those steps are skipped.
function scheduleOnlyFetch() {
  return async (url: string | URL | Request) => {
    const u = String(url)
    if (u.endsWith('/f1/2024.json')) {
      return new Response(readFileSync(resolve('test/fixtures/jolpica/schedule-2024.json'), 'utf8'), { status: 200 })
    }
    return new Response('not found', { status: 404 })
  }
}
const always404 = async () => new Response('x', { status: 404 })

describe('backfillSeasonData', () => {
  it('creates the backfilled season as NOT current and leaves the existing current season intact', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })

    const jolpica = new JolpicaClient('https://x', scheduleOnlyFetch())
    const openf1 = new OpenF1Client('https://x', always404)
    const wiki = new WikipediaClient('https://x', always404)
    await backfillSeasonData(2024, { jolpica, openf1, wiki })

    // The current season must still be 2026.
    expect(await seasons.getCurrent()).toMatchObject({ year: 2026, isCurrent: true })
    // The backfilled season exists but is not current.
    const all = await seasons.list()
    expect(all.find((s) => s.year === 2024)).toMatchObject({ year: 2024, isCurrent: false })
    // Events + sessions were created from the schedule.
    const evs = await events.listForSeason(2024)
    expect(evs.length).toBeGreaterThan(20)
    const round1 = evs.find((e) => e.round === 1)!
    const ss = await sessions.listForEvent(round1.id)
    expect(ss.find((s) => s.type === 'race')).toBeDefined()
  })
})
