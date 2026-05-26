import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictions from '../../src/repo/predictions.js'
import * as picks from '../../src/repo/predictionPicks.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() + 60_000),
    scheduledEnd: new Date(Date.now() + 60_000 + 2 * 60 * 60 * 1000),
    status: 'scheduled',
  openf1SessionKey: null
  })
  await drivers.upsertDriver({ code: 'VER', givenName: 'Max', familyName: 'Verstappen', nationality: 'NL', permanentNumber: 33, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  await drivers.upsertDriver({ code: 'HAM', givenName: 'Lewis', familyName: 'Hamilton', nationality: 'GB', permanentNumber: 44, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  const user = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
  return { user, ses }
}

describe('predictions repo', () => {
  it('inserts a prediction with picks and reads them back', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' }
    ])
    const got = await predictions.getByUserAndSession(user.id, ses.id)
    expect(got?.id).toBe(p.id)
    const list = await picks.listForPrediction(p.id)
    expect(list).toEqual([
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' }
    ])
  })

  it('replaces picks atomically', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [{ position: 1, driverCode: 'VER' }])
    await picks.replaceForPrediction(p.id, [
      { position: 1, driverCode: 'HAM' },
      { position: 2, driverCode: 'VER' }
    ])
    const list = await picks.listForPrediction(p.id)
    expect(list).toEqual([
      { position: 1, driverCode: 'HAM' },
      { position: 2, driverCode: 'VER' }
    ])
  })

  it('rejects duplicate (user, session)', async () => {
    const { user, ses } = await seed()
    await predictions.insertPrediction(user.id, ses.id)
    await expect(predictions.insertPrediction(user.id, ses.id)).rejects.toThrow(/duplicate|unique/i)
  })

  it('upserts via upsertPredictionWithPicks (idempotent submit)', async () => {
    const { user, ses } = await seed()
    const id1 = await predictions.upsertPredictionWithPicks(user.id, ses.id, [
      { position: 1, driverCode: 'VER' }
    ])
    const id2 = await predictions.upsertPredictionWithPicks(user.id, ses.id, [
      { position: 1, driverCode: 'HAM' }
    ])
    expect(id1).toBe(id2)
    const list = await picks.listForPrediction(id2)
    expect(list).toEqual([{ position: 1, driverCode: 'HAM' }])
  })

  it('deletes a prediction (cascades picks)', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [{ position: 1, driverCode: 'VER' }])
    await predictions.deleteByUserAndSession(user.id, ses.id)
    expect(await predictions.getByUserAndSession(user.id, ses.id)).toBeNull()
    expect(await picks.listForPrediction(p.id)).toEqual([])
  })

  it('lists all predictions+picks for a session', async () => {
    const { user, ses } = await seed()
    const u2 = await users.insertUser({ email: 't2@x.com', passwordHash: 'h', displayName: 'T2' })
    const p1 = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p1.id, [{ position: 1, driverCode: 'VER' }])
    const p2 = await predictions.insertPrediction(u2.id, ses.id)
    await picks.replaceForPrediction(p2.id, [{ position: 1, driverCode: 'HAM' }])

    const all = await predictions.listForSessionWithPicks(ses.id)
    const byUser = new Map(all.map((x) => [x.userId, x.picks]))
    expect(byUser.get(user.id)).toEqual([{ position: 1, driverCode: 'VER' }])
    expect(byUser.get(u2.id)).toEqual([{ position: 1, driverCode: 'HAM' }])
  })

  it('cascades from user delete', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [{ position: 1, driverCode: 'VER' }])
    await users.deleteById(user.id)
    expect(await predictions.getByUserAndSession(user.id, ses.id)).toBeNull()
  })
})
