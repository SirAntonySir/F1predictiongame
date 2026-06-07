import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import type { FastifyInstance } from 'fastify'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictionsRepo from '../../src/repo/predictions.js'

// Fake OpenF1 client. The route only ever calls getSessions / getDrivers /
// getPosition (LiveDeps is a Pick of those), so a plain object suffices —
// no need to spin up a real OpenF1Client with a stubbed fetch here.
function fakeOpenF1() {
  return {
    getSessions: async () => [
      { session_key: 777, session_name: 'Race', date_start: '2026-06-07T13:00:00Z' }
    ],
    getDrivers: async () => [
      { driver_number: 1, name_acronym: 'VER', first_name: 'Max', last_name: 'Verstappen', team_name: 'Red Bull Racing', team_colour: '3671c6' },
      { driver_number: 16, name_acronym: 'LEC', first_name: 'Charles', last_name: 'Leclerc', team_name: 'Ferrari', team_colour: 'e8002d' }
    ],
    getPosition: async () => [
      { driver_number: 1, position: 1, date: '2026-06-07T13:30:00Z' },
      { driver_number: 16, position: 2, date: '2026-06-07T13:30:00Z' }
    ]
  }
}

const auth = (token: string) => ({ authorization: `Bearer ${token}` })

async function signupAndToken(app: FastifyInstance) {
  const r = await app.inject({
    method: 'POST',
    url: '/api/auth/signup',
    payload: { email: `u-${Date.now()}-${Math.random()}@x.com`, password: 'hunter22', displayName: 'U' }
  })
  return { token: r.json().token as string, userId: r.json().user.id as string }
}

// Seed enough drivers so the FK on prediction_pick.driver_code is satisfied.
async function seedDrivers(codes: string[]) {
  for (const code of codes) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
}

async function seedSession(status: 'scheduled' | 'finished', openf1SessionKey: number | null) {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  // Start in the past, end in the future => an in-progress race when scheduled.
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() - 30 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 90 * 60 * 1000),
    status,
    openf1SessionKey
  })
}

describe('GET /api/sessions/:id/live', () => {
  let app: FastifyInstance
  beforeEach(async () => {
    app = await buildApp({ scheduler: null, openf1: fakeOpenF1() as any })
  })

  it('returns live order + my projected total for an in-progress race', async () => {
    await seedDrivers(['VER', 'LEC', 'HAM', 'NOR', 'PIA'])
    const ses = await seedSession('scheduled', 777)
    const { token, userId } = await signupAndToken(app)
    // 5-pick race prediction: P1 VER, P2 LEC, then 3 throwaway (seeded) codes.
    await predictionsRepo.upsertPredictionWithPicks(userId, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'LEC' },
      { position: 3, driverCode: 'HAM' },
      { position: 4, driverCode: 'NOR' },
      { position: 5, driverCode: 'PIA' }
    ])

    const res = await app.inject({ method: 'GET', url: `/api/sessions/${ses.id}/live`, headers: auth(token) })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.state).toBe('live')
    expect(body.order.map((r: any) => [r.position, r.driverCode])).toEqual([[1, 'VER'], [2, 'LEC']])
    // VER exact (3) + LEC exact (3) + 0 + 0 + 0, plus P1 team bonus (+2) = 8.
    expect(body.myProjected.pointsTotal).toBe(8)
  })

  it('401 without a token', async () => {
    const ses = await seedSession('scheduled', 777)
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${ses.id}/live` })
    expect(res.statusCode).toBe(401)
  })

  it('returns state=final for a finished session', async () => {
    const ses = await seedSession('finished', 777)
    const { token } = await signupAndToken(app)
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${ses.id}/live`, headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().state).toBe('final')
  })
})
