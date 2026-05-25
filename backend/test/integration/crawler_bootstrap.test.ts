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
})
