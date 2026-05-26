import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as users from '../../src/repo/users.js'
import * as picks from '../../src/repo/preseasonPicks.js'
import * as scores from '../../src/repo/scores.js'
import { runTick } from '../../src/crawler/tick.js'
import { OpenF1Client } from '../../src/openf1/client.js'

class FakeJolpica {
  async getRaceResults() {
    return {
      MRData: { RaceTable: { Races: [{
        season: '2026', round: '1', raceName: 'Bahrain',
        Results: [{
          position: '1',
          Driver: { driverId: 'VER', code: 'VER', givenName: 'M', familyName: 'V', nationality: 'NL', permanentNumber: '33', url: '' },
          Constructor: { constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' },
          grid: '1', laps: '1', status: 'Finished', Time: { time: '1:00:00' }, points: '25'
        }]
      }] } }
    }
  }
  async getQualifyingResults() { return null }
  async getSprintResults() { return null }
  async getSprintQualifyingResults() { return null }
  async getDriverStandings() {
    return {
      MRData: { StandingsTable: { season: '2026', StandingsLists: [{
        DriverStandings: [{
          position: '1', points: '25', wins: '1',
          Driver: { driverId: 'VER', code: 'VER', givenName: 'M', familyName: 'V', nationality: 'NL', permanentNumber: '33', url: '' },
          Constructors: [{ constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' }]
        }]
      }] } }
    }
  }
  async getConstructorStandings() {
    return {
      MRData: { StandingsTable: { season: '2026', StandingsLists: [{
        ConstructorStandings: [{
          position: '1', points: '25', wins: '1',
          Constructor: { constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' }
        }]
      }] } }
    }
  }
}
class FakeWiki {
  async getImageUrl() { return null }
}

describe('tick triggers preseason rescore', () => {
  it('after standings refresh, preseason scores appear for predicting users', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'B', hasSprint: false })
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date(Date.now() - 3 * 60 * 60 * 1000),
      scheduledEnd: new Date(Date.now() - 60 * 60 * 1000), status: 'scheduled',
    openf1SessionKey: null
    })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await standings.replaceDriverStandings(2026, [{ seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }])

    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })

    const noopOpenF1 = new OpenF1Client('https://example.invalid', async () => new Response(JSON.stringify([]), { status: 200 }))
    const summary = await runTick(new FakeJolpica() as any, new FakeWiki() as any, noopOpenF1)
    expect(summary.errors).toBe(0)

    const list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list).toHaveLength(7)
    expect(list.find((r) => r.category === 'wdc_wcc')!.pointsTotal).toBe(8)
  })
})
