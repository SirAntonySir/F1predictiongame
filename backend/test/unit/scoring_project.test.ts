import { describe, it, expect } from 'vitest'
import { projectTotal } from '../../src/scoring/project.js'
import type { SessionResultRow } from '../../src/domain/types.js'

function row(position: number, driverCode: string, constructorId: string): SessionResultRow {
  return { sessionId: 0, position, driverCode, driverName: driverCode, constructorId, constructorName: constructorId,
    raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
}

const order = [row(1, 'VER', 'red_bull'), row(2, 'LEC', 'ferrari'), row(3, 'NOR', 'mclaren'),
               row(4, 'PIA', 'mclaren'), row(5, 'RUS', 'mercedes')]

describe('projectTotal', () => {
  it('scores a full race pick set using backend rules (exact 3, wrongPos 1, +2 team bonus)', () => {
    // picks P1..P5; VER exact (3), LEC exact (3), PIA in top-5 wrong slot (1), HAM miss (0), RUS exact (3)
    // P1 pick VER -> winner VER same team -> team bonus +2  => 3+3+1+0+3 +2 = 12
    const picks = [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'LEC' },
      { position: 3, driverCode: 'PIA' }, { position: 4, driverCode: 'HAM' },
      { position: 5, driverCode: 'RUS' }
    ]
    expect(projectTotal('race', picks, order)).toBe(12)
  })

  it('returns null when the pick count does not match the session type', () => {
    expect(projectTotal('race', [{ position: 1, driverCode: 'VER' }], order)).toBeNull()
    expect(projectTotal('race', [], order)).toBeNull()
  })

  it('returns null for non-scorable types', () => {
    expect(projectTotal('fp1', [], order)).toBeNull()
  })
})
