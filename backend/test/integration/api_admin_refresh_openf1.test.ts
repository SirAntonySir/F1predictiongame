import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
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

function openf1WithDriver() {
  return new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
    if (url.includes('/drivers?session_key=9001')) {
      return { status: 200, body: [{
        driver_number: 4, name_acronym: 'VER', first_name: 'Max', last_name: 'Verstappen',
        team_name: 'Red Bull', headshot_url: 'https://example.com/ver.png', team_colour: '1E41FF'
      }] }
    }
    return { status: 200, body: [] }
  }))
}

let app: Awaited<ReturnType<typeof buildApp>>

beforeEach(async () => {
  app = await buildApp({ scheduler: null, openf1: openf1WithDriver() })
})

async function seed() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
  await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date('2024-03-02T15:00:00Z'),
    scheduledEnd: new Date('2024-03-02T17:00:00Z'),
    status: 'finished', openf1SessionKey: 9001
  })
  await drivers.upsertDriver({
    code: 'VER', givenName: 'Max', familyName: 'Verstappen',
    nationality: null, permanentNumber: 1, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
}

describe('POST /admin/refresh-openf1-metadata', () => {
  it('fills headshot_url and team_colour from OpenF1', async () => {
    await seed()
    const res = await app.inject({
      method: 'POST',
      url: '/admin/refresh-openf1-metadata',
      headers: { 'x-admin-token': 'local-dev-token' }
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.ok).toBe(true)
    expect(body.driversUpdated).toBeGreaterThanOrEqual(1)
    expect(body.constructorsUpdated).toBeGreaterThanOrEqual(1)

    const d = await drivers.getByCode('VER')
    expect(d?.headshotUrl).toBe('https://example.com/ver.png')
    const c = await constructors.getById('red_bull')
    expect(c?.teamColour).toBe('1E41FF')
  })

  it('returns 401 without admin token', async () => {
    await seed()
    const res = await app.inject({ method: 'POST', url: '/admin/refresh-openf1-metadata' })
    expect(res.statusCode).toBe(401)
  })
})
