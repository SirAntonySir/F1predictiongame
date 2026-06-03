import { describe, it, expect } from 'vitest'
import { scoreQualifying } from '../../../src/scoring/qualifying.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }
const NOR = { code: 'NOR', team: 'mclaren' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreQualifying', () => {
  it('all exact (3 + 3 + team bonus 1) = 7', () => {
    const picks = [{ position: 1, driverCode: VER.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition).toEqual([
      { position: 1, driverCode: VER.code, exact: true, wrongPos: false, points: 3 },
      { position: 2, driverCode: HAM.code, exact: true, wrongPos: false, points: 3 }
    ])
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
    expect(b.rule).toBe('qualifying-v1')
  })

  it('swapped P1/P2: both wrongPos (1 + 1), team bonus depends on P1', () => {
    const picks = [{ position: 1, driverCode: HAM.code }, { position: 2, driverCode: VER.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: HAM.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: VER.code, exact: false, wrongPos: true, points: 1 })
    // P1-pick HAM is mercedes; pole-actual VER is red_bull -> no team bonus
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('team bonus only: wrong driver, same team', () => {
    const RUS = { code: 'RUS', team: 'mercedes' }
    const picks = [{ position: 1, driverCode: RUS.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, HAM), f(2, RUS)]
    const b = scoreQualifying(picks, finishers)
    // P1-pick RUS is mercedes; pole-actual HAM is mercedes -> team bonus applies
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
    // Driver scoring: P1 RUS picked, RUS actually finished P2 -> wrongPos at P1; P2 HAM picked, HAM finished P1 -> wrongPos
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: RUS.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: HAM.code, exact: false, wrongPos: true, points: 1 })
  })

  it('wrong-pos requires driver to qualify in actual top-2, not just anywhere', () => {
    // HAM picked for P1 actually qualifies P8 → driver in result list but outside top-2 → 0 points.
    // VER picked for P2 finishes P1 → in top-2 → wrong-pos 1 point.
    const picks = [{ position: 1, driverCode: HAM.code }, { position: 2, driverCode: VER.code }]
    const finishers = [
      f(1, VER), f(2, NOR),
      { position: 8, driverCode: HAM.code, constructorId: HAM.team }
    ]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: HAM.code, exact: false, wrongPos: false, points: 0 })
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: VER.code, exact: false, wrongPos: true, points: 1 })
    // HAM (mercedes) picked for P1, VER (red_bull) on actual pole → no team bonus.
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('no matches at all: 0 points', () => {
    const picks = [{ position: 1, driverCode: NOR.code }, { position: 2, driverCode: NOR.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition.every((p) => p.points === 0)).toBe(true)
    expect(b.teamBonus.applied).toBe(false)
  })
})
