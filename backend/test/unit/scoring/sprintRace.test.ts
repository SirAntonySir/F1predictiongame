import { describe, it, expect } from 'vitest'
import { scoreSprintRace } from '../../../src/scoring/sprintRace.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }
const NOR = { code: 'NOR', team: 'mclaren' }
const PIA = { code: 'PIA', team: 'mclaren' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreSprintRace', () => {
  it('all exact (2 + 2 + 2 + team 1) = 7', () => {
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR)]
    const b = scoreSprintRace(picks, finishers)
    expect(b.perPosition.every((p) => p.exact)).toBe(true)
    expect(b.perPosition.reduce((s, p) => s + p.points, 0)).toBe(6)
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
  })

  it('partial podium and team bonus from teammate (only when teammate appears in finishers list)', () => {
    const picks = [
      { position: 1, driverCode: PIA.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: VER.code }
    ]
    // PIA didn't finish; scorer can't infer his team from finishers -> no team bonus.
    const finishers = [f(1, NOR), f(2, HAM), f(3, VER)]
    const b = scoreSprintRace(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: HAM.code, exact: true, wrongPos: false, points: 2 })
    expect(b.perPosition[2]).toEqual({ position: 3, driverCode: VER.code, exact: true, wrongPos: false, points: 2 })
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('wrong-pos requires driver to finish in actual sprint top-3, not just anywhere', () => {
    // VER picked for P1 finishes P5 → in result list but outside top-3 → 0 points.
    // HAM picked for P2 finishes P1 → in top-3 → wrong-pos 1 point.
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code }
    ]
    const finishers = [
      f(1, HAM), f(2, NOR), f(3, PIA),
      { position: 5, driverCode: VER.code, constructorId: VER.team }
    ]
    const b = scoreSprintRace(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: VER.code, exact: false, wrongPos: false, points: 0 })
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: HAM.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[2]).toEqual({ position: 3, driverCode: NOR.code, exact: false, wrongPos: true, points: 1 })
  })

  it('no points at all', () => {
    const picks = [
      { position: 1, driverCode: NOR.code },
      { position: 2, driverCode: NOR.code },
      { position: 3, driverCode: NOR.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, PIA)]
    const b = scoreSprintRace(picks, finishers)
    // NOR didn't finish at all
    expect(b.perPosition.every((p) => p.points === 0)).toBe(true)
    expect(b.teamBonus.applied).toBe(false)
  })
})
