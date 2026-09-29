import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 3
const WRONG_POS = 1
const TEAM_BONUS = 2
const RULE = 'race-v1'
// Wrong-pos window: a picked driver finishing anywhere in the actual top-5
// scores 1. Fixed by the rule, not by how many picks were submitted.
const TOP_N = 5

export function scoreRace(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const topN = TOP_N
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, driverCode: p.driverCode, exact: true, wrongPos: false, points: EXACT }
    }
    const driverInTopN = finishers.some((f) => f.driverCode === p.driverCode && f.position <= topN)
    if (driverInTopN) {
      return { position: p.position, driverCode: p.driverCode, exact: false, wrongPos: true, points: WRONG_POS }
    }
    return { position: p.position, driverCode: p.driverCode, exact: false, wrongPos: false, points: 0 }
  })

  const p1Pick = picks.find((p) => p.position === 1)
  const winner = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && winner) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === winner.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
