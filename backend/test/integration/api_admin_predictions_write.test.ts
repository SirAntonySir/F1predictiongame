import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as users from '../../src/repo/users.js'
import * as predictions from '../../src/repo/predictions.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: null })
  for (const d of ['VER', 'LEC', 'HAM']) {
    await drivers.upsertDriver({ code: d, givenName: d, familyName: d, nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  const u = await users.insertUser({ email: 'p@x.com', passwordHash: 'h', displayName: 'Pat' })
  await predictions.upsertPredictionWithPicks(u.id, ses.id, [{ position: 1, driverCode: 'VER' }])
  return { sid: ses.id, uid: u.id }
}

describe('admin prediction writes', () => {
  it('requires the admin token', async () => {
    const { sid, uid } = await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'DELETE', url: `/admin/predictions/${uid}/${sid}` })
    expect(r.statusCode).toBe(401)
    await app.close()
  })

  it('edits picks then deletes the prediction', async () => {
    const { sid, uid } = await seed()
    const app = await buildApp({ scheduler: null })

    let r = await app.inject({ method: 'PUT', url: `/admin/predictions/${uid}/${sid}/picks`, headers: TOKEN, payload: { picks: [{ position: 1, driverCode: 'LEC' }, { position: 2, driverCode: 'HAM' }] } })
    expect(r.statusCode).toBe(200)
    let preds = await predictions.listForSessionWithPicks(sid)
    expect(preds.find((p) => p.userId === uid)!.picks.map((x) => x.driverCode)).toEqual(['LEC', 'HAM'])

    r = await app.inject({ method: 'DELETE', url: `/admin/predictions/${uid}/${sid}`, headers: TOKEN })
    expect(r.statusCode).toBe(200)
    preds = await predictions.listForSessionWithPicks(sid)
    expect(preds.find((p) => p.userId === uid)).toBeUndefined()
    await app.close()
  })

  it('rejects an unknown driver and non-prefix positions (422)', async () => {
    const { sid, uid } = await seed()
    const app = await buildApp({ scheduler: null })
    let r = await app.inject({ method: 'PUT', url: `/admin/predictions/${uid}/${sid}/picks`, headers: TOKEN, payload: { picks: [{ position: 1, driverCode: 'NOPE' }] } })
    expect(r.statusCode).toBe(422)
    r = await app.inject({ method: 'PUT', url: `/admin/predictions/${uid}/${sid}/picks`, headers: TOKEN, payload: { picks: [{ position: 2, driverCode: 'VER' }] } })
    expect(r.statusCode).toBe(422)
    await app.close()
  })
})
