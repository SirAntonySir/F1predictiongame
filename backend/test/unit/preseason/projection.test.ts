import { describe, it, expect } from 'vitest'
import {
  projectTruthsFromSnapshot,
  projectCategoryScore,
} from '../../../src/preseason/projection.js'
import type { SessionResultRow, DriverStanding, ConstructorStanding, Session } from '../../../src/domain/types.js'

type Stored<T> = T & { id: number }

const sess = (id: number, type: Session['type']): Stored<Session> => ({
  id,
  eventId: 1,
  type,
  scheduledStart: new Date(2026, 2, 8),
  scheduledEnd: new Date(2026, 2, 8, 2),
  status: 'finished',
  openf1SessionKey: null,
})

const result = (
  sessionId: number,
  driverCode: string,
  constructorId: string,
  position: number,
  status: string | null = null,
  fastestLap: string | null = null,
): SessionResultRow => ({
  sessionId,
  position,
  driverCode,
  driverName: driverCode,
  constructorId,
  constructorName: constructorId,
  raceTime: null,
  status,
  points: null,
  fastestLap,
  fastestLapTime: null,
  fastestLapSpeed: null,
  q1: null,
  q2: null,
  q3: null,
})

describe('projectTruthsFromSnapshot', () => {
  it('returns observed truths for derivable categories and null for subjective ones', () => {
    const sessions = [sess(1, 'race'), sess(2, 'qualifying'), sess(3, 'race')]
    const results = [
      // R1 race: VER wins with fastest lap, HAM DNF
      result(1, 'VER', 'red_bull', 1, 'Finished', '1'),
      result(1, 'HAM', 'mercedes', 20, 'Retired'),
      // Q2: VER pole
      result(2, 'VER', 'red_bull', 1),
      // R3 race: VER fastest lap again, HAM engine
      result(3, 'VER', 'red_bull', 1, 'Finished', '1'),
      result(3, 'HAM', 'mercedes', 20, 'Engine'),
    ]
    const drivers: DriverStanding[] = [
      { seasonYear: 2026, driverCode: 'VER', position: 1, points: 50, wins: 2, constructorId: 'red_bull' },
      { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 0,  wins: 0, constructorId: 'mercedes' },
    ]
    const constructors: ConstructorStanding[] = [
      { seasonYear: 2026, constructorId: 'red_bull', position: 1, points: 50, wins: 2 },
      { seasonYear: 2026, constructorId: 'mercedes', position: 2, points: 0,  wins: 0 },
    ]

    const truths = projectTruthsFromSnapshot(results, sessions, drivers, constructors)
    expect(truths.dnf.driverCode).toBe('HAM')
    expect(truths.poles.driverCode).toBe('VER')
    expect(truths.fastest_lap.driverCode).toBe('VER')
    expect(truths.wdc_wcc.driverCode).toBe('VER')
    expect(truths.wdc_wcc.constructorId).toBe('red_bull')
    expect(truths.surprise).toBeNull()
    expect(truths.disappointment).toBeNull()
    expect(truths.standings.drivers[0]).toBe('VER')
    expect(truths.standings.constructors[0]).toBe('red_bull')
  })
})

describe('projectCategoryScore', () => {
  it('returns 0 for subjective categories regardless of pick', () => {
    const r = projectCategoryScore('surprise', { driverCode: 'VER', constructorId: null }, null)
    expect(r.projectedPoints).toBe(0)
  })

  it('mirrors scorePreseasonCategory when a projected truth exists', () => {
    const truth = { driverCode: 'VER', constructorId: 'red_bull' }
    const r = projectCategoryScore('dnf', { driverCode: 'VER', constructorId: 'red_bull' }, truth)
    // 4 (driver match) + 4 (team match) = 8
    expect(r.projectedPoints).toBe(8)
  })

  it('partial pick returns half', () => {
    const truth = { driverCode: 'VER', constructorId: 'red_bull' }
    const r = projectCategoryScore('dnf', { driverCode: 'HAM', constructorId: 'red_bull' }, truth)
    expect(r.projectedPoints).toBe(4)
  })
})
