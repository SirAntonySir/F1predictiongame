import { describe, it, expect } from 'vitest'
import { scoreSprintShootout } from '../../../src/scoring/sprintShootout.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreSprintShootout', () => {
  it('exact P1: 1 + team bonus 1 = 2', () => {
    const picks = [{ position: 1, driverCode: VER.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreSprintShootout(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, driverCode: VER.code, exact: true, wrongPos: false, points: 1 })
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
  })

  it('wrong driver, no team match: 0', () => {
    const picks = [{ position: 1, driverCode: VER.code }]
    const finishers = [f(1, HAM)]
    const b = scoreSprintShootout(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)
    expect(b.teamBonus.applied).toBe(false)
  })

  it('team match only requires picked driver to appear in finishers list', () => {
    // HAM picked for P1; RUS (same team mercedes) actually won. HAM is not in finishers,
    // so the scorer cannot infer his team from input -> team bonus does NOT apply.
    // (Mirrors the sprintRace design: rescorer is responsible for synthesizing a full
    // finishers list including non-finishers if it wants to support this case.)
    const RUS = { code: 'RUS', team: 'mercedes' }
    const picks = [{ position: 1, driverCode: HAM.code }]
    const finishers = [f(1, RUS)]
    const b = scoreSprintShootout(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)  // HAM didn't finish anywhere
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })
})
