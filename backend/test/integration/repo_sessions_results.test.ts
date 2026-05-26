import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as results from '../../src/repo/results.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

async function seed() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  await drivers.upsertDriver({
    code: 'VER', givenName: 'Max', familyName: 'Verstappen',
    nationality: 'Dutch', permanentNumber: 33, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: 'Austrian',
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  return ev
}

describe('sessions repo', () => {
  it('upserts a session and marks it finished', async () => {
    const ev = await seed()
    const start = new Date('2024-03-02T15:00:00Z')
    const end = new Date('2024-03-02T17:00:00Z')
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: start, scheduledEnd: end, status: 'scheduled',
    openf1SessionKey: null
    })
    expect(ses.id).toBeGreaterThan(0)
    await sessions.markFinished(ses.id!)
    const fetched = await sessions.getById(ses.id!)
    expect(fetched?.status).toBe('finished')
  })

  it('lists candidate sessions for tick (scheduled, past end+30min, not practice)', async () => {
    const ev = await seed()
    const past = new Date(Date.now() - 60 * 60 * 1000)        // 1h ago
    const past2 = new Date(Date.now() - 3 * 60 * 60 * 1000)   // 3h ago
    const future = new Date(Date.now() + 60 * 60 * 1000)      // 1h ahead

    await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: past2, scheduledEnd: past, status: 'scheduled', openf1SessionKey: null })
    await sessions.upsertSession({ eventId: ev.id, type: 'qualifying', scheduledStart: new Date(), scheduledEnd: future, status: 'scheduled', openf1SessionKey: null })

    const candidates = await sessions.listCandidates()
    expect(candidates.map((c) => c.type)).toEqual(['race'])
  })

  it('includes race / qualifying / sprint sessions whose end is more than 7 days in the past', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled',
    openf1SessionKey: null
    })
    await sessions.upsertSession({
      eventId: ev.id, type: 'qualifying', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled',
    openf1SessionKey: null
    })
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled',
    openf1SessionKey: null
    })
    const types = (await sessions.listCandidates()).map((c) => c.type).sort()
    expect(types).toEqual(['qualifying', 'race', 'sprint'])
  })

  it('excludes sprint_quali sessions whose end is more than 7 days in the past', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled',
    openf1SessionKey: null
    })
    expect(await sessions.listCandidates()).toEqual([])
  })

  it('includes sprint_quali sessions whose end is within the last 7 days', async () => {
    const ev = await seed()
    const recent = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali', scheduledStart: recent, scheduledEnd: recent, status: 'scheduled',
    openf1SessionKey: null
    })
    const candidates = await sessions.listCandidates()
    expect(candidates.map((c) => c.type)).toEqual(['sprint_quali'])
  })

  it('still excludes finished past sessions from candidates', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled',
    openf1SessionKey: null
    })
    await sessions.markFinished(ses.id!)
    expect(await sessions.listCandidates()).toEqual([])
  })

  it('excludes practice sessions from candidates', async () => {
    const ev = await seed()
    const past = new Date(Date.now() - 60 * 60 * 1000)
    await sessions.upsertSession({ eventId: ev.id, type: 'fp1', scheduledStart: past, scheduledEnd: past, status: 'scheduled', openf1SessionKey: null })
    await sessions.upsertSession({ eventId: ev.id, type: 'fp2', scheduledStart: past, scheduledEnd: past, status: 'scheduled', openf1SessionKey: null })
    await sessions.upsertSession({ eventId: ev.id, type: 'fp3', scheduledStart: past, scheduledEnd: past, status: 'scheduled', openf1SessionKey: null })
    expect(await sessions.listCandidates()).toEqual([])
  })

  it('nextScheduled returns soonest future scheduled session', async () => {
    const ev = await seed()
    const soon = new Date(Date.now() + 60 * 60 * 1000)
    const later = new Date(Date.now() + 24 * 60 * 60 * 1000)
    await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: later, scheduledEnd: later, status: 'scheduled', openf1SessionKey: null })
    await sessions.upsertSession({ eventId: ev.id, type: 'qualifying', scheduledStart: soon, scheduledEnd: soon, status: 'scheduled', openf1SessionKey: null })
    const next = await sessions.nextScheduled()
    expect(next?.type).toBe('qualifying')
  })

  it('lists sessions for an event ordered by scheduledStart', async () => {
    const ev = await seed()
    const t1 = new Date('2024-03-01T10:00:00Z')
    const t2 = new Date('2024-03-02T10:00:00Z')
    const t3 = new Date('2024-03-03T10:00:00Z')
    await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: t3, scheduledEnd: t3, status: 'scheduled', openf1SessionKey: null })
    await sessions.upsertSession({ eventId: ev.id, type: 'qualifying', scheduledStart: t2, scheduledEnd: t2, status: 'scheduled', openf1SessionKey: null })
    await sessions.upsertSession({ eventId: ev.id, type: 'fp1', scheduledStart: t1, scheduledEnd: t1, status: 'scheduled', openf1SessionKey: null })
    const list = await sessions.listForEvent(ev.id)
    expect(list.map((s) => s.type)).toEqual(['fp1', 'qualifying', 'race'])
  })
})

describe('results repo', () => {
  it('upserts results and overwrites on conflict', async () => {
    const ev = await seed()
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date(), scheduledEnd: new Date(),
      status: 'scheduled',
    openf1SessionKey: null
    })
    const rows = [
      {
        sessionId: ses.id!, position: 1, driverCode: 'VER', driverName: 'Max Verstappen',
        constructorId: 'red_bull', constructorName: 'Red Bull',
        raceTime: '1:31:44.742', status: 'Finished', points: 25,
        fastestLap: '45', fastestLapTime: '1:30.000', fastestLapSpeed: '210.0',
        q1: null, q2: null, q3: null
      }
    ]
    await results.replaceForSession(ses.id!, rows)
    await results.replaceForSession(ses.id!, rows.map((r) => ({ ...r, points: 26 })))
    const fetched = await results.listForSession(ses.id!)
    expect(fetched).toHaveLength(1)
    expect(fetched[0]!.points).toBe(26)
  })

  it('empty rows on a session that had results clears them', async () => {
    const ev = await seed()
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: new Date(), scheduledEnd: new Date(), status: 'scheduled',
    openf1SessionKey: null
    })
    await results.replaceForSession(ses.id!, [{
      sessionId: ses.id!, position: 1, driverCode: 'VER', driverName: 'Max',
      constructorId: 'red_bull', constructorName: 'Red Bull',
      raceTime: null, status: null, points: 25,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: null, q2: null, q3: null
    }])
    expect((await results.listForSession(ses.id!)).length).toBe(1)
    await results.replaceForSession(ses.id!, [])
    expect((await results.listForSession(ses.id!)).length).toBe(0)
  })
})
