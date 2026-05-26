import { describe, it, expect } from 'vitest'
import { runBootstrap } from '../../src/crawler/bootstrap.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as sessions from '../../src/repo/sessions.js'
import * as events from '../../src/repo/events.js'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

function fx(rel: string): string {
  return readFileSync(resolve(rel), 'utf8')
}

function jolpicaFake(): JolpicaClient {
  // Reuses the captured 2024 schedule fixture from the existing jolpica tests.
  const body = fx('test/fixtures/jolpica/schedule-2024.json')
  return new JolpicaClient(
    'https://example.invalid',
    (async () => new Response(body, { status: 200 })) as unknown as typeof fetch
  )
}

function openf1Fake(sessionsBody: string): OpenF1Client {
  return new OpenF1Client(
    'https://api.openf1.org/v1',
    (async (url: string | URL) => {
      const u = url.toString()
      if (u.includes('/sessions?year=')) return new Response(sessionsBody, { status: 200 })
      return new Response('[]', { status: 200 })
    }) as unknown as typeof fetch
  )
}

describe('OpenF1 bootstrap-time mapping', () => {
  it('writes openf1_session_key for sessions present in OpenF1', async () => {
    // Build a tiny OpenF1 sessions payload that overlaps with Jolpica round 1 (Bahrain).
    // Bahrain race is 2024-03-02. session_name = "Race".
    const openf1Body = JSON.stringify([
      { session_key: 9001, session_name: 'Race', date_start: '2024-03-02T15:00:00+00:00', year: 2024 },
      { session_key: 9002, session_name: 'Qualifying', date_start: '2024-03-01T16:00:00+00:00', year: 2024 }
    ])

    await runBootstrap(jolpicaFake(), 2024, openf1Fake(openf1Body))

    const round1 = await events.getByRound(2024, 1)
    expect(round1).toBeTruthy()
    const round1Sessions = await sessions.listForEvent(round1!.id)
    const race = round1Sessions.find((s) => s.type === 'race')
    const quali = round1Sessions.find((s) => s.type === 'qualifying')
    const fp1 = round1Sessions.find((s) => s.type === 'fp1')
    expect(race?.openf1SessionKey).toBe(9001)
    expect(quali?.openf1SessionKey).toBe(9002)
    expect(fp1?.openf1SessionKey).toBeNull() // not in our OpenF1 fake response
  })

  it('does not fail when OpenF1 returns an empty array', async () => {
    await runBootstrap(jolpicaFake(), 2024, openf1Fake('[]'))
    const round1 = await events.getByRound(2024, 1)
    const round1Sessions = await sessions.listForEvent(round1!.id)
    for (const s of round1Sessions) {
      expect(s.openf1SessionKey).toBeNull()
    }
  })
})
