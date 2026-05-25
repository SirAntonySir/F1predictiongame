import { describe, it, expect } from 'vitest'
import { scoreSession } from '../../../src/scoring/index.js'
import type { SessionType } from '../../../src/domain/types.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreSession dispatcher', () => {
  it('dispatches to scoreRace', () => {
    const picks = Array.from({ length: 5 }, (_, i) => ({ position: i + 1, driverCode: VER.code }))
    const finishers = [f(1, VER)]
    const b = scoreSession('race', picks, finishers)
    expect(b.rule).toBe('race-v1')
  })

  it('dispatches to scoreQualifying', () => {
    const picks = [{ position: 1, driverCode: VER.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreSession('qualifying', picks, finishers)
    expect(b.rule).toBe('qualifying-v1')
  })

  it('throws on unknown session type', () => {
    expect(() => scoreSession('fp1' as SessionType, [], [])).toThrow(/not scorable/i)
  })

  it('throws on wrong pick count for type', () => {
    const tooFew = [{ position: 1, driverCode: VER.code }]  // race needs 5
    expect(() => scoreSession('race', tooFew, [])).toThrow(/expected 5 picks/i)
  })
})
