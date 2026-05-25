import type { PreseasonCategory, PreseasonScoreBreakdown, PreseasonPickInput } from './types.js'

const POINTS_PER_MATCH = 4

const RULES: Record<PreseasonCategory, string> = {
  surprise:        'preseason-surprise-v1',
  disappointment:  'preseason-disappointment-v1',
  dnf:             'preseason-dnf-v1',
  poles:           'preseason-poles-v1',
  fastest_lap:     'preseason-fastest-lap-v1',
  wdc_wcc:         'preseason-wdc-wcc-v1'
}

export function scoreSinglePick(
  category: PreseasonCategory,
  pick: PreseasonPickInput,
  truth: PreseasonPickInput
): PreseasonScoreBreakdown {
  const driverCorrect = pick.driverCode !== null && truth.driverCode !== null && pick.driverCode === truth.driverCode
  const teamCorrect   = pick.constructorId !== null && truth.constructorId !== null && pick.constructorId === truth.constructorId

  const driverPoints = driverCorrect ? POINTS_PER_MATCH : 0
  const teamPoints   = teamCorrect   ? POINTS_PER_MATCH : 0

  return {
    driver: { picked: pick.driverCode,    truth: truth.driverCode,    correct: driverCorrect, points: driverPoints },
    team:   { picked: pick.constructorId, truth: truth.constructorId, correct: teamCorrect,   points: teamPoints },
    pointsTotal: driverPoints + teamPoints,
    rule: RULES[category]
  }
}
