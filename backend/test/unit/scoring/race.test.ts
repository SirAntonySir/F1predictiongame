import { describe, it, expect } from 'vitest'
import { scoreRace } from '../../../src/scoring/race.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }
const NOR = { code: 'NOR', team: 'mclaren' }
const PIA = { code: 'PIA', team: 'mclaren' }
const RUS = { code: 'RUS', team: 'mercedes' }
const PER = { code: 'PER', team: 'red_bull' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreRace', () => {
  it('all 5 exact + team bonus (3*5 + 2) = 17', () => {
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR), f(4, PIA), f(5, RUS)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition.reduce((s, p) => s + p.points, 0)).toBe(15)
    expect(b.teamBonus).toEqual({ applied: true, points: 2 })
  })

  it('mixed exact + wrong-pos, no team bonus', () => {
    // VER picked for P1, actually finished P2 -> wrongPos at P1
    // HAM picked for P2, actually finished P1 -> wrongPos at P2
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [f(1, HAM), f(2, VER), f(3, NOR), f(4, PIA), f(5, RUS)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: VER.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: HAM.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[2]).toEqual({ position: 3, driverCode: NOR.code, exact: true, wrongPos: false, points: 3 })
    // VER picked for P1, HAM (mercedes) won. VER is red_bull -> no team bonus
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('team-only bonus (right team, wrong driver in P1)', () => {
    // PER picked for P1, VER (same team red_bull) actually won. PER didn't finish at all.
    const picks = [
      { position: 1, driverCode: PER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR), f(4, PIA), f(5, RUS)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)  // PER not in finishers, no inferrable team -> no team bonus
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('wrong-pos requires driver to finish in actual top-5, not just anywhere', () => {
    // VER picked for P1 finishes P10 → driver finished, but outside top-5 → 0 points.
    // HAM picked for P2 finishes P3 → still in top-5 → wrong-pos 1 point.
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [
      f(1, NOR), f(2, PIA), f(3, HAM), f(4, RUS), f(5, PER),
      { position: 10, driverCode: VER.code, constructorId: VER.team }
    ]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: VER.code, exact: false, wrongPos: false, points: 0 })
    expect(b.perPosition[1]).toEqual({ position: 2, driverCode: HAM.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[2]).toEqual({ position: 3, driverCode: NOR.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[3]).toEqual({ position: 4, driverCode: PIA.code, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[4]).toEqual({ position: 5, driverCode: RUS.code, exact: false, wrongPos: true, points: 1 })
  })

  it('fewer than 5 finishers (DNFs): missing positions score 0', () => {
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    // Only 3 finishers
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0].points).toBe(3)
    expect(b.perPosition[1].points).toBe(3)
    expect(b.perPosition[2].points).toBe(3)
    expect(b.perPosition[3].points).toBe(0)
    expect(b.perPosition[4].points).toBe(0)
    expect(b.teamBonus).toEqual({ applied: true, points: 2 })
  })
})
