import { describe, it, expect, beforeEach } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: null })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  await constructors.upsertConstructor({ id: 'ferrari', name: 'Ferrari', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  await drivers.upsertDriver({ code: 'LEC', givenName: 'C', familyName: 'L', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  return ses.id
}

function row(sessionId: number, position: number, driverCode: string, driverName: string, constructorId: string, constructorName: string) {
  return { sessionId, position, driverCode, driverName, constructorId, constructorName, raceTime: null, status: 'Finished', points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
}

describe('single-row result helpers', () => {
  let sid: number
  beforeEach(async () => { sid = await seed() })

  it('inserts, gets, updates and deletes a row', async () => {
    await results.insertResult(row(sid, 1, 'VER', 'Max Verstappen', 'red_bull', 'Red Bull'))
    const got = await results.getResult(sid, 1)
    expect(got?.driverCode).toBe('VER')

    const updated = await results.updateResultFields(sid, 1, { points: 25, status: 'Finished' })
    expect(updated.points).toBe(25)

    await results.deleteResult(sid, 1)
    expect(await results.getResult(sid, 1)).toBeNull()
  })

  it('updateResultFields throws when the row is missing', async () => {
    await expect(results.updateResultFields(sid, 99, { points: 1 })).rejects.toThrow()
  })
})
