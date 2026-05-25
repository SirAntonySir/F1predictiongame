import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 1
const TEAM_BONUS = 1
const RULE = 'sprint-shootout-v1'

export function scoreSprintShootout(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, exact: true, wrongPos: false, points: EXACT }
    }
    return { position: p.position, exact: false, wrongPos: false, points: 0 }
  })

  const p1Pick = picks.find((p) => p.position === 1)
  const p1Actual = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && p1Actual) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === p1Actual.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
