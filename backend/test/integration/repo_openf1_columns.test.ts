import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

async function seed() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  return events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
}

describe('OpenF1 columns', () => {
  it('session.openf1SessionKey roundtrips via setter', async () => {
    const ev = await seed()
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date('2024-03-02T15:00:00Z'),
      scheduledEnd: new Date('2024-03-02T17:00:00Z'),
      status: 'scheduled',
      openf1SessionKey: null
    })
    await sessions.setOpenF1SessionKey(ses.id!, 9876)
    const fetched = await sessions.getById(ses.id!)
    expect(fetched?.openf1SessionKey).toBe(9876)
  })

  it('driver.headshotUrl roundtrips via setter and listMissingHeadshot filters', async () => {
    await drivers.upsertDriver({
      code: 'VER', givenName: 'Max', familyName: 'Verstappen',
      nationality: 'Dutch', permanentNumber: 33, wikipediaUrl: null,
      imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
    expect((await drivers.listMissingHeadshot()).map((d) => d.code)).toEqual(['VER'])
    await drivers.setHeadshotUrl('VER', 'https://example.com/ver.png')
    expect((await drivers.listMissingHeadshot())).toEqual([])
    expect((await drivers.getByCode('VER'))?.headshotUrl).toBe('https://example.com/ver.png')
  })

  it('constructor.teamColour roundtrips via setter and listMissingTeamColour filters', async () => {
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull', nationality: 'Austrian',
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
    })
    expect((await constructors.listMissingTeamColour()).map((c) => c.id)).toEqual(['red_bull'])
    await constructors.setTeamColour('red_bull', '1E41FF')
    expect((await constructors.listMissingTeamColour())).toEqual([])
    expect((await constructors.getById('red_bull'))?.teamColour).toBe('1E41FF')
  })
})
