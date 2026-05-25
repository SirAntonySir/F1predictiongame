import type { PreseasonCategory, PreseasonPickInput } from './types.js'
import { scoreSinglePick } from './singlePick.js'
import { scoreStandings } from './standings.js'
import type { PreseasonScoreBreakdown } from './types.js'

export type { PreseasonCategory, PreseasonPickInput, PreseasonScoreBreakdown } from './types.js'
export { scoreSinglePick, scoreStandings }

const VALID_CATEGORIES: ReadonlyArray<PreseasonCategory> = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'
]

export function scorePreseasonCategory(
  category: PreseasonCategory,
  pick: PreseasonPickInput,
  truth: PreseasonPickInput
): PreseasonScoreBreakdown {
  if (!VALID_CATEGORIES.includes(category)) {
    throw new Error(`Unknown preseason category: ${category}`)
  }
  return scoreSinglePick(category, pick, truth)
}
