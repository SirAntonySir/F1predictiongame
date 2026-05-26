import type { PreseasonCategory, SessionType } from '../../domain/types.js'

export type RacePicks = {
  // 2 picks for quali (P1, P2); empty array = player skipped this session
  quali: { position: number; driverCode: string }[]
  // 1 pick for sprint shootout (P1); empty = skipped
  sprintQuali: { position: number; driverCode: string }[]
  // 3 picks for sprint race (P1..P3); empty = skipped
  sprint: { position: number; driverCode: string }[]
  // 5 picks for race (P1..P5); empty = skipped
  race: { position: number; driverCode: string }[]
  // Excel-computed points per row (for validation only)
  excelPoints: { quali: number; sprint: number; race: number }
}

export type ParsedPlayer = {
  excelName: string
  // Indexed by canonical event name (DB event.name); missing key = race not in DB or fully skipped
  racePicks: Record<string, RacePicks>
  preseasonStandings: {
    constructors: { position: number; constructorId: string }[]   // 11 entries
    drivers:      { position: number; driverCode: string }[]      // 22 entries
  }
  preseasonSingle: Partial<Record<PreseasonCategory, {
    driverCode: string | null
    constructorId: string | null
  }>>
}

export type ParsedSeason = {
  seasonYear: number
  players: ParsedPlayer[]
}

export const SESSION_TYPE_BY_KIND: Record<keyof Omit<RacePicks, 'excelPoints'>, SessionType> = {
  quali: 'qualifying',
  sprintQuali: 'sprint_quali',
  sprint: 'sprint',
  race: 'race'
}
