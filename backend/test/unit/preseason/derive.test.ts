import { describe, it, expect } from 'vitest'
import {
  deriveMostDnfs,
  derivePolesitter,
  deriveMostFastestLaps,
  deriveWdcWcc,
  deriveFinalStandings
} from '../../../src/preseason/derive.js'
import type { SessionResultRow, DriverStanding, ConstructorStanding } from '../../../src/domain/types.js'
import type { StoredSession } from '../../../src/repo/sessions.js'

function r(sessionId: number, position: number, code: string, team: string, opts: Partial<SessionResultRow> = {}): SessionResultRow {
  return {
    sessionId, position, driverCode: code, driverName: code,
    constructorId: team, constructorName: team,
    raceTime: null, status: 'Finished', points: null,
    fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null,
    ...opts
  }
}

function s(id: number, type: StoredSession['type']): StoredSession {
  return {
    id, eventId: 1, type,
    scheduledStart: new Date(2026, 0, 1),
    scheduledEnd: new Date(2026, 0, 1, 2),
    status: 'finished'
  } as StoredSession
}

describe('deriveMostDnfs', () => {
  it('counts DNF statuses across all race + sprint sessions', () => {
    const sessions = [s(1, 'race'), s(2, 'race'), s(3, 'sprint'), s(4, 'qualifying')]
    const results = [
      r(1, 1, 'VER', 'red_bull'),
      r(1, 20, 'HAM', 'mercedes', { status: 'Retired' }),
      r(1, 19, 'RUS', 'mercedes', { status: 'Engine' }),
      r(2, 18, 'HAM', 'mercedes', { status: 'Collision' }),
      r(3, 18, 'HAM', 'mercedes', { status: 'Accident' }),  // sprint counts too
      r(4, 20, 'HAM', 'mercedes', { status: 'Engine' })     // qualifying SKIPPED
    ]
    const result = deriveMostDnfs(results, sessions)
    expect(result.driverCode).toBe('HAM')  // 3 DNFs (race1, race2, sprint3) — quali skipped
    expect(result.constructorId).toBe('mercedes')  // 4 (HAM x3 + RUS x1)
  })
})

describe('derivePolesitter', () => {
  it('returns driver with most position-1 in qualifying sessions', () => {
    const sessions = [s(1, 'qualifying'), s(2, 'qualifying'), s(3, 'sprint_quali'), s(4, 'race')]
    const results = [
      r(1, 1, 'VER', 'red_bull'),
      r(2, 1, 'VER', 'red_bull'),
      r(3, 1, 'HAM', 'mercedes'),  // sprint_quali — excluded from main poles
      r(4, 1, 'NOR', 'mclaren')    // race — excluded
    ]
    const result = derivePolesitter(results, sessions)
    expect(result.driverCode).toBe('VER')
    expect(result.constructorId).toBe('red_bull')
  })
})

describe('deriveMostFastestLaps', () => {
  it('counts fastestLap = "1" in race sessions only', () => {
    const sessions = [s(1, 'race'), s(2, 'race'), s(3, 'sprint')]
    const results = [
      r(1, 1, 'VER', 'red_bull', { fastestLap: '1' }),
      r(1, 2, 'HAM', 'mercedes', { fastestLap: '2' }),
      r(2, 5, 'VER', 'red_bull', { fastestLap: '1' }),
      r(3, 1, 'HAM', 'mercedes', { fastestLap: '1' })  // sprint excluded
    ]
    const result = deriveMostFastestLaps(results, sessions)
    expect(result.driverCode).toBe('VER')
  })
})

describe('deriveWdcWcc', () => {
  it('picks position=1 from each standings table', () => {
    const drivers: DriverStanding[] = [
      { seasonYear: 2026, driverCode: 'VER', position: 1, points: 400, wins: 10, constructorId: 'red_bull' },
      { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 300, wins: 4, constructorId: 'mercedes' }
    ]
    const constructors: ConstructorStanding[] = [
      { seasonYear: 2026, constructorId: 'mclaren',  position: 1, points: 700, wins: 8 },
      { seasonYear: 2026, constructorId: 'red_bull', position: 2, points: 600, wins: 10 }
    ]
    const result = deriveWdcWcc(drivers, constructors)
    expect(result.driverCode).toBe('VER')
    expect(result.constructorId).toBe('mclaren')
  })
})

describe('deriveFinalStandings', () => {
  it('returns ordered lists', () => {
    const drivers: DriverStanding[] = [
      { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 300, wins: 4, constructorId: 'mercedes' },
      { seasonYear: 2026, driverCode: 'VER', position: 1, points: 400, wins: 10, constructorId: 'red_bull' }
    ]
    const constructors: ConstructorStanding[] = [
      { seasonYear: 2026, constructorId: 'red_bull', position: 2, points: 600, wins: 10 },
      { seasonYear: 2026, constructorId: 'mclaren',  position: 1, points: 700, wins: 8 }
    ]
    const r = deriveFinalStandings(drivers, constructors)
    expect(r.drivers).toEqual([
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'HAM' }
    ])
    expect(r.constructors).toEqual([
      { position: 1, entityId: 'mclaren' },
      { position: 2, entityId: 'red_bull' }
    ])
  })
})
