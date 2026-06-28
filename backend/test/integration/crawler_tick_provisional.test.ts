import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as users from '../../src/repo/users.js'
import * as predictions from '../../src/repo/predictions.js'
import * as scores from '../../src/repo/scores.js'
import * as results from '../../src/repo/results.js'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

const wikiNoop = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))
// Jolpica has nothing yet — forces the OpenF1 paths.
const jolpicaEmpty = new JolpicaClient('https://example.invalid', staticFetch(() => ({
  status: 200, body: { MRData: { RaceTable: { Races: [] } } }
})))

/// OpenF1 with NO official session_result yet, but live /position timing showing
/// a finishing order — the provisional window.
function openf1Live(order: Array<{ num: number; code: string; team: string }>) {
  return new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
    if (url.includes('/session_result?')) return { status: 200, body: [] }
    if (url.includes('/position?')) {
      return { status: 200, body: order.map((o, i) => ({
        driver_number: o.num, position: i + 1, date: `2026-05-01T14:0${i}:00Z`
      })) }
    }
    if (url.includes('/drivers?')) {
      return { status: 200, body: order.map((o) => ({
        driver_number: o.num, name_acronym: o.code, first_name: o.code, last_name: o.code,
        team_name: o.team, headshot_url: null, team_colour: null
      })) }
    }
    return { status: 200, body: [] } // /laps etc.
  }))
}

async function seedScheduledRaceWithKey() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain GP', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  for (const code of ['VER', 'PER']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: code, nationality: null,
      permanentNumber: 1, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }
  ])
  // Past its scheduled end so it's a tick candidate; OpenF1-keyed → fast path.
  const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: past, scheduledEnd: new Date(Date.now() - 60 * 60 * 1000),
    status: 'scheduled', openf1SessionKey: 9100
  })
}

describe('tick persists provisional results', () => {
  it('writes results + scores from live timing without marking the session finished', async () => {
    const ses = await seedScheduledRaceWithKey()
    const u = await users.insertUser({ email: 'p@x.com', passwordHash: 'h', displayName: 'P' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id!, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'PER' },
      { position: 3, driverCode: 'VER' },
      { position: 4, driverCode: 'VER' },
      { position: 5, driverCode: 'VER' }
    ])

    const summary = await runTick(
      jolpicaEmpty, wikiNoop,
      openf1Live([{ num: 1, code: 'VER', team: 'Red Bull' }, { num: 11, code: 'PER', team: 'Red Bull' }])
    )

    expect(summary.errors).toBe(0)
    expect(summary.sessionsProvisional).toBe(1)
    expect(summary.sessionsFinished).toBe(0)

    // Results persisted (provisional, source=openf1) but session stays scheduled.
    const persisted = await results.listForSession(ses.id!)
    expect(persisted.map((r) => r.driverCode)).toEqual(['VER', 'PER'])
    expect(persisted.every((r) => r.source === 'openf1')).toBe(true)
    const after = await sessions.getById(ses.id!)
    expect(after!.status).toBe('scheduled')

    // The leaderboard-feeding score now exists.
    const userScores = await scores.listForUser(u.id, 2026)
    expect(userScores).toHaveLength(1)
    expect(userScores[0]!.pointsTotal).toBeGreaterThan(0)
  })

  it('upgrades a provisional session to finished once the official result lands', async () => {
    const ses = await seedScheduledRaceWithKey()
    await runTick(
      jolpicaEmpty, wikiNoop,
      openf1Live([{ num: 1, code: 'VER', team: 'Red Bull' }, { num: 11, code: 'PER', team: 'Red Bull' }])
    )
    expect((await sessions.getById(ses.id!))!.status).toBe('scheduled')

    // Next tick: OpenF1 now publishes the official session_result → finalize.
    const openf1Official = new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
      if (url.includes('/session_result?')) {
        return { status: 200, body: [
          { position: 1, driver_number: 1, duration: [], gap_to_leader: [], dnf: false, dns: false, dsq: false, number_of_laps: 57, meeting_key: 1, session_key: 9100 },
          { position: 2, driver_number: 11, duration: [], gap_to_leader: [], dnf: false, dns: false, dsq: false, number_of_laps: 57, meeting_key: 1, session_key: 9100 }
        ] }
      }
      if (url.includes('/drivers?')) {
        return { status: 200, body: [
          { driver_number: 1, name_acronym: 'VER', first_name: 'Max', last_name: 'Verstappen', team_name: 'Red Bull', headshot_url: null, team_colour: null },
          { driver_number: 11, name_acronym: 'PER', first_name: 'Sergio', last_name: 'Perez', team_name: 'Red Bull', headshot_url: null, team_colour: null }
        ] }
      }
      return { status: 200, body: [] }
    }))

    const summary = await runTick(jolpicaEmpty, wikiNoop, openf1Official)
    expect(summary.sessionsFinished).toBe(1)
    expect(summary.sessionsProvisional).toBe(0)
    expect((await sessions.getById(ses.id!))!.status).toBe('finished')
  })
})
