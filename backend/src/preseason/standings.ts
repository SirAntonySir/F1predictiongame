import type { PreseasonScoreBreakdown, StandingsEntry } from './types.js'

const DRIVER_POINTS_PER_CORRECT = 3
const TEAM_POINTS_PER_CORRECT = 4
const RULE = 'preseason-standings-v1'

export function scoreStandings(
  driverPicks: StandingsEntry[],
  constructorPicks: StandingsEntry[],
  driverTruth: StandingsEntry[],
  constructorTruth: StandingsEntry[]
): PreseasonScoreBreakdown {
  const driverTruthByPos = new Map(driverTruth.map((e) => [e.position, e.entityId]))
  const teamTruthByPos = new Map(constructorTruth.map((e) => [e.position, e.entityId]))

  const perPosition: NonNullable<PreseasonScoreBreakdown['perPosition']> = []
  let total = 0

  for (const p of driverPicks) {
    const truth = driverTruthByPos.get(p.position) ?? null
    const correct = truth !== null && truth === p.entityId
    const points = correct ? DRIVER_POINTS_PER_CORRECT : 0
    perPosition.push({ position: p.position, picked: p.entityId, truth, correct, points })
    total += points
  }

  for (const p of constructorPicks) {
    const truth = teamTruthByPos.get(p.position) ?? null
    const correct = truth !== null && truth === p.entityId
    const points = correct ? TEAM_POINTS_PER_CORRECT : 0
    // distinguish driver vs team rows by position+entityId nature; the consumer separates by entity-id format
    perPosition.push({ position: p.position, picked: p.entityId, truth, correct, points })
    total += points
  }

  return { perPosition, pointsTotal: total, rule: RULE }
}
