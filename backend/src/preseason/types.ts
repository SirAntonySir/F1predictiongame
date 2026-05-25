import type { PreseasonCategory, PreseasonScoreBreakdown } from '../domain/types.js'

export type { PreseasonCategory, PreseasonScoreBreakdown }

export type PreseasonPickInput = {
  driverCode: string | null
  constructorId: string | null
}

export type StandingsEntry = {
  position: number
  entityId: string  // driver_code or constructor_id
}
