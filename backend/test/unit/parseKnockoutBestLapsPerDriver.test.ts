import { describe, it, expect } from 'vitest'
import { parseKnockoutBestLapsPerDriver, type OpenF1DriverLookup } from '../../src/openf1/parsers.js'

const VER: OpenF1DriverLookup = {
  driverNumber: 1, code: 'VER', givenName: 'Max', familyName: 'V',
  teamName: 'Red Bull', headshotUrl: null, teamColour: null
}
const NOR: OpenF1DriverLookup = {
  driverNumber: 4, code: 'NOR', givenName: 'Lando', familyName: 'N',
  teamName: 'McLaren', headshotUrl: null, teamColour: null
}
const drivers = [VER, NOR]

describe('parseKnockoutBestLapsPerDriver', () => {
  it('matches each q1/q2/q3 string against the lap with the same lap_duration', () => {
    const rows = [
      { driverCode: 'VER', q1: '1:30.500', q2: '1:30.000', q3: '1:29.800' },
      { driverCode: 'NOR', q1: '1:30.700', q2: '1:30.200', q3: null }
    ]
    const laps = [
      // VER: warmup + three flying laps across the three knockouts
      { driver_number: 1, lap_duration: 100.0, duration_sector_1: 33, duration_sector_2: 33, duration_sector_3: 34, lap_number: 1, is_pit_out_lap: true },
      { driver_number: 1, lap_duration: 90.500, duration_sector_1: 30.0, duration_sector_2: 30.0, duration_sector_3: 30.500, lap_number: 3, is_pit_out_lap: false },
      { driver_number: 1, lap_duration: 90.000, duration_sector_1: 29.8, duration_sector_2: 29.9, duration_sector_3: 30.3, lap_number: 8, is_pit_out_lap: false },
      { driver_number: 1, lap_duration: 89.800, duration_sector_1: 29.7, duration_sector_2: 29.8, duration_sector_3: 30.3, lap_number: 14, is_pit_out_lap: false },
      // NOR: only Q1 + Q2
      { driver_number: 4, lap_duration: 90.700, duration_sector_1: 30.2, duration_sector_2: 30.2, duration_sector_3: 30.3, lap_number: 4, is_pit_out_lap: false },
      { driver_number: 4, lap_duration: 90.200, duration_sector_1: 30.0, duration_sector_2: 30.0, duration_sector_3: 30.2, lap_number: 9, is_pit_out_lap: false }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out).toHaveLength(5)
    const ver3 = out.find((b) => b.driverCode === 'VER' && b.knockout === 3)!
    expect(ver3.lapMs).toBe(89800)
    expect(ver3.s1Ms).toBe(29700)
    expect(ver3.lapNumber).toBe(14)
    const ver1 = out.find((b) => b.driverCode === 'VER' && b.knockout === 1)!
    const ver2 = out.find((b) => b.driverCode === 'VER' && b.knockout === 2)!
    expect(ver1.lapNumber).toBe(3)
    expect(ver1.lapMs).toBe(90500)
    expect(ver2.lapNumber).toBe(8)
    expect(ver2.lapMs).toBe(90000)
    expect(out.find((b) => b.driverCode === 'NOR' && b.knockout === 3)).toBeUndefined()
  })

  it('skips knockouts with no matching lap (e.g. session_result reconciled from Jolpica)', () => {
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: null, q3: null }]
    const laps = [
      // No lap matches q1 — OpenF1 only has a 1:30.510 entry; tolerance is 2ms
      { driver_number: 1, lap_duration: 90.510, duration_sector_1: 30, duration_sector_2: 30, duration_sector_3: 30.510, lap_number: 4, is_pit_out_lap: false }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out).toHaveLength(0)
  })

  it('tolerates ±2ms rounding between Jolpica session_result and OpenF1 laps', () => {
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: null, q3: null }]
    const laps = [
      { driver_number: 1, lap_duration: 90.501, duration_sector_1: 30, duration_sector_2: 30, duration_sector_3: 30.501, lap_number: 4, is_pit_out_lap: false }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out).toHaveLength(1)
    expect(out[0]!.knockout).toBe(1)
    expect(out[0]!.lapMs).toBe(90501)
  })

  it('excludes pit-out laps from candidates', () => {
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: null, q3: null }]
    const laps = [
      // A pit-out lap happens to match q1 — must NOT be picked
      { driver_number: 1, lap_duration: 90.500, duration_sector_1: 33, duration_sector_2: 30, duration_sector_3: 27.5, lap_number: 1, is_pit_out_lap: true }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out).toHaveLength(0)
  })

  it('does not bind the same physical lap to two knockouts when q-times are within tolerance', () => {
    // VER posts Q1 = 1:30.500 and Q2 = 1:30.501 (1ms apart, well within the
    // ±2ms tolerance). Without used-lap tracking, the single 1:30.500 lap
    // would be bound to both knockouts. With it, the lap is consumed by Q1
    // and Q2 falls through with no match.
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: '1:30.501', q3: null }]
    const laps = [
      { driver_number: 1, lap_duration: 90.500, duration_sector_1: 30, duration_sector_2: 30, duration_sector_3: 30.5, lap_number: 5, is_pit_out_lap: false }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out).toHaveLength(1)
    expect(out[0]!.knockout).toBe(1)
  })

  it('emits nothing for a driver in qualiResults with no laps in the payload', () => {
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: null, q3: null }]
    const out = parseKnockoutBestLapsPerDriver([], drivers, rows)
    expect(out).toHaveLength(0)
  })

  it('emits nothing for a driver who has laps but is missing from qualiResults', () => {
    // NOR ran flying laps but isn't in qualiResults (e.g. test driver / FP2
    // substitute). No row should leak through.
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: null, q3: null }]
    const laps = [
      { driver_number: 4, lap_duration: 90.700, duration_sector_1: 30.2, duration_sector_2: 30.2, duration_sector_3: 30.3, lap_number: 4, is_pit_out_lap: false }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out.every((b) => b.driverCode !== 'NOR')).toBe(true)
  })

  it('prefers the earlier lap_number when two laps have equal delta', () => {
    // Two flying laps with identical lap_duration; without the lapNumber
    // tiebreaker, the choice would depend on iteration order. Q1 should
    // bind the earlier lap.
    const rows = [{ driverCode: 'VER', q1: '1:30.500', q2: null, q3: null }]
    const laps = [
      { driver_number: 1, lap_duration: 90.500, duration_sector_1: 30, duration_sector_2: 30, duration_sector_3: 30.5, lap_number: 10, is_pit_out_lap: false },
      { driver_number: 1, lap_duration: 90.500, duration_sector_1: 30, duration_sector_2: 30, duration_sector_3: 30.5, lap_number: 3, is_pit_out_lap: false }
    ]
    const out = parseKnockoutBestLapsPerDriver(laps, drivers, rows)
    expect(out).toHaveLength(1)
    expect(out[0]!.lapNumber).toBe(3)
  })
})
