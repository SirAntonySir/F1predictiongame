import { describe, it, expect } from 'vitest'
import { parseLivePositions, resolveOpenF1SessionKey } from '../../src/openf1/live.js'
import type { OpenF1DriverLookup } from '../../src/openf1/parsers.js'
import type { StoredSession } from '../../src/repo/sessions.js'

const drivers: OpenF1DriverLookup[] = [
  { driverNumber: 1, code: 'VER', givenName: 'Max', familyName: 'Verstappen', teamName: 'Red Bull Racing', headshotUrl: null, teamColour: null },
  { driverNumber: 16, code: 'LEC', givenName: 'Charles', familyName: 'Leclerc', teamName: 'Ferrari', headshotUrl: null, teamColour: null }
]

describe('parseLivePositions', () => {
  it('keeps the latest position per driver and joins driver info', () => {
    const raw = [
      { driver_number: 1, position: 2, date: '2026-06-07T13:00:00Z' },
      { driver_number: 16, position: 1, date: '2026-06-07T13:00:00Z' },
      { driver_number: 1, position: 1, date: '2026-06-07T13:05:00Z' }, // later → wins
      { driver_number: 16, position: 2, date: '2026-06-07T13:05:00Z' }
    ]
    const out = parseLivePositions(raw, drivers)
    expect(out.map((r) => [r.position, r.driverCode])).toEqual([[1, 'VER'], [2, 'LEC']])
    expect(out[0]).toMatchObject({ constructorId: 'red_bull_racing', constructorName: 'Red Bull Racing', driverName: 'Max Verstappen' })
  })

  it('skips drivers not present in the lookup and tolerates empty input', () => {
    expect(parseLivePositions([], drivers)).toEqual([])
    expect(parseLivePositions([{ driver_number: 99, position: 1, date: 'x' }], drivers)).toEqual([])
  })
})

describe('resolveOpenF1SessionKey', () => {
  const base: StoredSession = {
    id: 5, eventId: 1, type: 'race',
    scheduledStart: new Date('2026-06-07T13:00:00Z'),
    scheduledEnd: new Date('2026-06-07T15:00:00Z'),
    status: 'scheduled', openf1SessionKey: null
  }

  it('returns the stored key without calling OpenF1', async () => {
    let called = false
    const client = { getSessions: async () => { called = true; return [] } } as any
    const key = await resolveOpenF1SessionKey({ ...base, openf1SessionKey: 4242 }, client, async () => {})
    expect(key).toBe(4242)
    expect(called).toBe(false)
  })

  it('matches by session_name + nearest date_start, then persists', async () => {
    const client = {
      getSessions: async () => [
        { session_key: 11, session_name: 'Qualifying', date_start: '2026-06-07T13:00:00Z' },
        { session_key: 22, session_name: 'Race', date_start: '2026-06-07T13:02:00Z' },
        { session_key: 33, session_name: 'Race', date_start: '2026-06-14T13:00:00Z' }
      ]
    } as any
    let persisted: [number, number | null] | null = null
    const key = await resolveOpenF1SessionKey(base, client, async (id, k) => { persisted = [id, k] })
    expect(key).toBe(22)
    expect(persisted).toEqual([5, 22])
  })

  it('returns null when nothing matches within the window', async () => {
    const client = { getSessions: async () => [{ session_key: 1, session_name: 'Race', date_start: '2026-01-01T00:00:00Z' }] } as any
    expect(await resolveOpenF1SessionKey(base, client, async () => {})).toBeNull()
  })
})
