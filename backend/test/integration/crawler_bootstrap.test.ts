import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { runBootstrap } from '../../src/crawler/bootstrap.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'

function fixtureFetch(name: string) {
  return async (_url: string | URL | Request) => {
    const body = readFileSync(resolve('test/fixtures/jolpica', name), 'utf8')
    return new Response(body, { status: 200 })
  }
}

// schedule-2024 with [mutate] applied to its Races array (and MRData, for
// tampering with the pagination total).
function mutatedScheduleFetch(mutate: (races: any[], mr: any) => void) {
  return async (_url: string | URL | Request) => {
    const raw = JSON.parse(readFileSync(resolve('test/fixtures/jolpica', 'schedule-2024.json'), 'utf8'))
    mutate(raw.MRData.RaceTable.Races, raw.MRData)
    return new Response(JSON.stringify(raw), { status: 200 })
  }
}

// schedule-2024 with China (round 5) reworked into a regular weekend.
function chinaWithoutSprintFetch() {
  return mutatedScheduleFetch((races) => {
    const china = races.find((r: { round: string }) => r.round === '5')
    delete china.Sprint
    delete china.SprintQualifying
  })
}

// Mirrors 2026: a relocated regular weekend lands mid-season ("Bahrain Grand
// Prix in Malaysia") and every later round shifts up by one.
function malaysiaInsertedAtRound5Fetch() {
  return mutatedScheduleFetch((races, mr) => {
    for (const r of races) if (Number(r.round) >= 5) r.round = String(Number(r.round) + 1)
    races.splice(4, 0, {
      season: '2024',
      round: '5',
      raceName: 'Bahrain Grand Prix in Malaysia',
      Circuit: {
        circuitId: 'sepang',
        circuitName: 'Sepang International Circuit',
        Location: { lat: '2.76083', long: '101.738', locality: 'Kuala Lumpur', country: 'Malaysia' }
      },
      date: '2024-04-14', time: '07:00:00Z',
      FirstPractice: { date: '2024-04-12', time: '03:30:00Z' },
      SecondPractice: { date: '2024-04-12', time: '07:00:00Z' },
      ThirdPractice: { date: '2024-04-13', time: '03:30:00Z' },
      Qualifying: { date: '2024-04-13', time: '07:00:00Z' }
    })
    mr.total = String(races.length)
  })
}

// schedule-2024 with Imola (round 7) cancelled and later rounds closing up.
function imolaCancelledFetch() {
  return mutatedScheduleFetch((races, mr) => {
    races.splice(races.findIndex((r: { round: string }) => r.round === '7'), 1)
    for (const r of races) if (Number(r.round) > 7) r.round = String(Number(r.round) - 1)
    mr.total = String(races.length)
  })
}

async function sessionIdsByType(eventId: number): Promise<Record<string, number>> {
  return Object.fromEntries((await sessions.listForEvent(eventId)).map((s) => [s.type, s.id]))
}

describe('runBootstrap', () => {
  it('populates season + events + sessions from the schedule', async () => {
    const client = new JolpicaClient('https://x', fixtureFetch('schedule-2024.json'))
    await runBootstrap(client, 2024)

    const cur = await seasons.getCurrent()
    expect(cur).toMatchObject({ year: 2024, isCurrent: true })

    const evList = await events.listForSeason(2024)
    expect(evList.length).toBeGreaterThan(20)

    const bahrain = evList.find((e) => e.round === 1)
    expect(bahrain).toBeDefined()

    const bahrainSessions = await sessions.listForEvent(bahrain!.id)
    expect(bahrainSessions.find((s) => s.type === 'race')).toBeDefined()
    expect(bahrainSessions.find((s) => s.type === 'qualifying')).toBeDefined()
    expect(bahrainSessions.find((s) => s.type === 'fp1')).toBeDefined()
  })

  it('is idempotent (running twice does not duplicate)', async () => {
    const client = new JolpicaClient('https://x', fixtureFetch('schedule-2024.json'))
    await runBootstrap(client, 2024)
    await runBootstrap(client, 2024)
    const evList = await events.listForSeason(2024)
    const bahrain = evList.find((e) => e.round === 1)
    const bahrainSessions = await sessions.listForEvent(bahrain!.id)
    const raceCount = bahrainSessions.filter((s) => s.type === 'race').length
    expect(raceCount).toBe(1)
  })

  it('marks sprint weekends with hasSprint=true', async () => {
    const client = new JolpicaClient('https://x', fixtureFetch('schedule-2024.json'))
    await runBootstrap(client, 2024)
    const china = await events.getByRound(2024, 5)
    expect(china?.hasSprint).toBe(true)
  })

  it('prunes sessions that dropped off the schedule', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    await runBootstrap(new JolpicaClient('https://x', chinaWithoutSprintFetch()), 2024)
    const china = await events.getByRound(2024, 5)
    expect(china?.hasSprint).toBe(false)
    const types = (await sessions.listForEvent(china!.id)).map((s) => s.type)
    expect(types).not.toContain('sprint')
    expect(types).not.toContain('sprint_quali')
    expect(types).toContain('race')
  })

  it('keeps a dropped session that already finished', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    const china = await events.getByRound(2024, 5)
    const sprint = (await sessions.listForEvent(china!.id)).find((s) => s.type === 'sprint')!
    await sessions.markFinished(sprint.id)
    await runBootstrap(new JolpicaClient('https://x', chinaWithoutSprintFetch()), 2024)
    const types = (await sessions.listForEvent(china!.id)).map((s) => s.type)
    expect(types).toContain('sprint')
    expect(types).not.toContain('sprint_quali')
  })

  it('keeps each Grand Prix on its own row when a round is inserted mid-season', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    const china = (await events.getByRound(2024, 5))!
    const chinaSessions = await sessionIdsByType(china.id)
    const abuDhabi = (await events.getByRound(2024, 24))!

    await runBootstrap(new JolpicaClient('https://x', malaysiaInsertedAtRound5Fetch()), 2024)

    // China moved to round 6 with the very same session rows, so picks made
    // on them stay attached to China.
    const china2 = (await events.getById(china.id))!
    expect(china2).toMatchObject({ name: 'Chinese Grand Prix', round: 6, hasSprint: true })
    expect(await sessionIdsByType(china.id)).toEqual(chinaSessions)

    // The inserted weekend is a new row carrying only its own sessions — no
    // sprint left over from the Grand Prix that used to hold round 5.
    const malaysia = (await events.getByRound(2024, 5))!
    expect(malaysia.id).not.toBe(china.id)
    expect(malaysia).toMatchObject({ name: 'Bahrain Grand Prix in Malaysia', hasSprint: false })
    expect(Object.keys(await sessionIdsByType(malaysia.id)).sort())
      .toEqual(['fp1', 'fp2', 'fp3', 'qualifying', 'race'])

    expect((await events.getByRound(2024, 25))?.id).toBe(abuDhabi.id)
    expect(await events.listForSeason(2024)).toHaveLength(25)
  })

  it('drops a cancelled Grand Prix and closes up the rounds', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    const imola = (await events.getByRound(2024, 7))!
    const monaco = (await events.getByRound(2024, 8))!
    const monacoSessions = await sessionIdsByType(monaco.id)

    await runBootstrap(new JolpicaClient('https://x', imolaCancelledFetch()), 2024)

    expect(await events.getById(imola.id)).toBeNull()
    expect((await events.getByRound(2024, 7))?.id).toBe(monaco.id)
    expect(await sessionIdsByType(monaco.id)).toEqual(monacoSessions)
    expect(await events.listForSeason(2024)).toHaveLength(23)
  })

  it('keeps a cancelled Grand Prix that already ran, out of the way of the new rounds', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    const imola = (await events.getByRound(2024, 7))!
    const imolaRace = (await sessions.listForEvent(imola.id)).find((s) => s.type === 'race')!
    await sessions.markFinished(imolaRace.id)
    const monaco = (await events.getByRound(2024, 8))!

    await runBootstrap(new JolpicaClient('https://x', imolaCancelledFetch()), 2024)

    const kept = await events.getById(imola.id)
    expect(kept?.name).toBe('Emilia Romagna Grand Prix')
    expect((await events.getByRound(2024, 7))?.id).toBe(monaco.id)
    const scheduledRounds = (await events.listForSeason(2024)).map((e) => e.round).filter((r) => r <= 23)
    expect(scheduledRounds).toHaveLength(23)

    // Stable across the weekly re-runs — parked once, not pushed further out.
    await runBootstrap(new JolpicaClient('https://x', imolaCancelledFetch()), 2024)
    expect((await events.getById(imola.id))?.round).toBe(kept!.round)
  })

  it('keeps a renamed Grand Prix on its row (same circuit)', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    const imola = (await events.getByRound(2024, 7))!
    await runBootstrap(new JolpicaClient('https://x', mutatedScheduleFetch((races) => {
      races.find((r: { round: string }) => r.round === '7').raceName = 'Imola Grand Prix'
    })), 2024)
    expect(await events.getById(imola.id)).toMatchObject({ round: 7, name: 'Imola Grand Prix' })
  })

  it('refuses a truncated schedule instead of dropping the missing rounds', async () => {
    await runBootstrap(new JolpicaClient('https://x', fixtureFetch('schedule-2024.json')), 2024)
    const truncated = new JolpicaClient('https://x', mutatedScheduleFetch((races) => {
      races.splice(10) // total still says 24
    }))
    await expect(runBootstrap(truncated, 2024)).rejects.toThrow(/truncated/i)
    expect(await events.listForSeason(2024)).toHaveLength(24)
  })
})
