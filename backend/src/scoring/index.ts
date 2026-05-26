import type { SessionType } from '../domain/types.js'
import { scoreQualifying } from './qualifying.js'
// Sprint Quali scoring is disabled — the source spreadsheet has no SQ column and
// users have no way to "guess" the single SQ pole position. Keep the scorer module
// importable so re-enabling later is a one-line revert (uncomment the import + the
// dispatch case + the EXPECTED_PICKS entry below).
// import { scoreSprintShootout } from './sprintShootout.js'
import { scoreSprintRace } from './sprintRace.js'
import { scoreRace } from './race.js'
import type { Pick, Finisher, ScoreBreakdown } from './types.js'

export type { Pick, Finisher, ScoreBreakdown } from './types.js'

const EXPECTED_PICKS: Partial<Record<SessionType, number>> = {
  qualifying: 2,
  // sprint_quali: 1,
  sprint: 3,
  race: 5
}

export function scoreSession(
  type: SessionType,
  picks: Pick[],
  finishers: Finisher[]
): ScoreBreakdown {
  const expected = EXPECTED_PICKS[type]
  if (expected === undefined) {
    throw new Error(`Session type ${type} is not scorable`)
  }
  if (picks.length !== expected) {
    throw new Error(`Session type ${type} expected ${expected} picks, got ${picks.length}`)
  }
  switch (type) {
    case 'qualifying':    return scoreQualifying(picks, finishers)
    // case 'sprint_quali':  return scoreSprintShootout(picks, finishers)
    case 'sprint':        return scoreSprintRace(picks, finishers)
    case 'race':          return scoreRace(picks, finishers)
    default:              throw new Error(`Session type ${type} is not scorable`)
  }
}

export function isScorableSessionType(type: SessionType): boolean {
  return EXPECTED_PICKS[type] !== undefined
}

export function picksRequiredFor(type: SessionType): number | null {
  return EXPECTED_PICKS[type] ?? null
}
