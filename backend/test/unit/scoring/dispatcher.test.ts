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

  it('throws on too many picks for type', () => {
    const tooMany = Array.from({ length: 6 }, (_, i) => ({ position: i + 1, driverCode: VER.code }))
    expect(() => scoreSession('race', tooMany, [])).toThrow(/at most 5 picks/i)
  })

  it('throws on zero picks', () => {
    expect(() => scoreSession('race', [], [])).toThrow(/at least 1 pick/i)
  })

  // Partial sets happen in reality (late/partial submissions backfilled by the
  // league owner). Filled positions score normally; empty ones just can't score.
  it('scores a partial race set (filled positions only)', () => {
    const partial = [{ position: 1, driverCode: VER.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreSession('race', partial, finishers)
    expect(b.rule).toBe('race-v1')
    expect(b.perPosition).toHaveLength(2)
    expect(b.perPosition.every((p) => p.exact)).toBe(true)
  })
})
