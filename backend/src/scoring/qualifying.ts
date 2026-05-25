import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 3
const WRONG_POS = 1
const TEAM_BONUS = 1
const RULE = 'qualifying-v1'

export function scoreQualifying(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, exact: true, wrongPos: false, points: EXACT }
    }
    const driverFinishedSomewhere = finishers.some((f) => f.driverCode === p.driverCode)
    if (driverFinishedSomewhere) {
      return { position: p.position, exact: false, wrongPos: true, points: WRONG_POS }
    }
    return { position: p.position, exact: false, wrongPos: false, points: 0 }
  })

  // Team bonus: P1-pick's team == pole-actual's team
  const p1Pick = picks.find((p) => p.position === 1)
  const poleActual = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && poleActual) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === poleActual.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
