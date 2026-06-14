import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as bestLaps from '../../src/repo/bestLaps.js'

async function seedSession(type: 'qualifying' | 'fp1' = 'qualifying') {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
  })
  await drivers.upsertDriver({
    code: 'VER', givenName: 'Max', familyName: 'V', nationality: null, permanentNumber: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type,
    scheduledStart: new Date(), scheduledEnd: new Date(),
    status: 'finished', openf1SessionKey: null
  })
  return ses.id!
}

describe('bestLaps repo — knockout column', () => {
  it('round-trips three knockout rows for a single driver in qualifying', async () => {
    const id = await seedSession('qualifying')
    await bestLaps.replaceForSession(id, [
      { driverCode: 'VER', knockout: 1, lapMs: 90500, s1Ms: 30000, s2Ms: 30000, s3Ms: 30500, lapNumber: 3 },
      { driverCode: 'VER', knockout: 2, lapMs: 90000, s1Ms: 29800, s2Ms: 29900, s3Ms: 30300, lapNumber: 8 },
      { driverCode: 'VER', knockout: 3, lapMs: 89800, s1Ms: 29700, s2Ms: 29800, s3Ms: 30300, lapNumber: 14 }
    ])
    const rows = await bestLaps.listForSessions([id])
    expect(rows).toHaveLength(3)
    expect(rows.map((r) => r.knockout).sort()).toEqual([1, 2, 3])
    const q3 = rows.find((r) => r.knockout === 3)!
    expect(q3.lapMs).toBe(89800)
    expect(q3.s1Ms).toBe(29700)
  })

  it('round-trips knockout=0 for non-quali sessions', async () => {
    const id = await seedSession('fp1')
    await bestLaps.replaceForSession(id, [
      { driverCode: 'VER', knockout: 0, lapMs: 92000, s1Ms: null, s2Ms: null, s3Ms: null, lapNumber: 4 }
    ])
    const rows = await bestLaps.listForSessions([id])
    expect(rows).toHaveLength(1)
    expect(rows[0]!.knockout).toBe(0)
  })
})
