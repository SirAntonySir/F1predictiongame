import * as XLSX from 'xlsx'
import { mapDriverCode, mapEventName, EVENTS_TO_SKIP } from './mappings.js'
import type { RacePicks } from './types.js'

export const RACE_HEADER_ROW           = 4
export const RACE_START_COL            = 3
export const RACE_COLS_EACH            = 6
export const STANDINGS_HEADER_ROW      = 30
export const STANDINGS_FIRST_DATA_ROW  = 33
export const STANDINGS_LAST_DATA_ROW   = 54
export const STANDINGS_COLS_PER_PLAYER = 4
export const STANDINGS_FIRST_TEAMS_COL = 3
// Preseason single-pick categories: one row per player, starting at Jan = R7, +1 per player
export const PRESEASON_SINGLE_ROW_START = 7
// Per-race picks: first player Jan starts at row 70 (name) → quali R72, sprint R73, race R74; stride 7
export const PLAYER_FIRST_NAME_ROW      = 70
export const PLAYER_ROW_STRIDE          = 7
export const PLAYER_QUALI_OFFSET        = 2
export const PLAYER_SPRINT_OFFSET       = 3
export const PLAYER_RACE_OFFSET         = 4
export const PLAYERS_IN_ORDER = [
  'Jan','Lukas','Jakob','Simon','Juli','Jonas','Janine','Jana','Anton','David','Merlin'
] as const

export type Sheet = XLSX.WorkSheet

export function readCell(ws: Sheet, row: number, col: number): string | null {
  const ref = XLSX.utils.encode_cell({ r: row - 1, c: col - 1 })
  const cell = (ws as Record<string, XLSX.CellObject | undefined>)[ref]
  if (!cell || cell.v === null || cell.v === undefined) return null
  const s = String(cell.v).trim()
  return s.length === 0 ? null : s
}

export function readNumber(ws: Sheet, row: number, col: number): number | null {
  const s = readCell(ws, row, col)
  if (s === null) return null
  const n = Number(s)
  return Number.isFinite(n) ? n : null
}

export function isSkipMarker(s: string | null): boolean {
  if (s === null) return false
  return s.trim() === '---'
}

/**
 * Convert an ordered list of cell values to a pick list starting at `startPosition`.
 * Returns [] if every cell is empty or " ---" (player did not tip).
 * Throws if partially filled, contains an unknown driver code, or has duplicates.
 */
export function parsePickList(cells: (string | null)[], startPosition: number): { position: number; driverCode: string }[] {
  const allEmpty = cells.every((c) => c === null || isSkipMarker(c))
  if (allEmpty) return []
  const picks: { position: number; driverCode: string }[] = []
  const seen = new Set<string>()
  for (let i = 0; i < cells.length; i++) {
    const cell = cells[i]
    if (cell === null || isSkipMarker(cell)) {
      throw new Error(`incomplete pick list at index ${i} (expected driver code, got ${JSON.stringify(cell)})`)
    }
    const code = mapDriverCode(cell)
    if (seen.has(code)) throw new Error(`duplicate driver in pick list: ${code}`)
    seen.add(code)
    picks.push({ position: startPosition + i, driverCode: code })
  }
  return picks
}

export type PlayerBlockRows = { qualiRow: number; sprintRow: number; raceRow: number }

/**
 * Reads the per-race tipping block for one player. Returns picks keyed by the *Excel*
 * race header (e.g. "Australia"), not the DB event name — caller does the DB mapping.
 * Skips events in EVENTS_TO_SKIP entirely (no key in the result).
 */
export function parsePlayerRaceBlock(ws: Sheet, rows: PlayerBlockRows): Record<string, RacePicks> {
  const out: Record<string, RacePicks> = {}
  // Walk race header columns left-to-right
  for (let col = RACE_START_COL; ; col += RACE_COLS_EACH) {
    const header = readCell(ws, RACE_HEADER_ROW, col)
    if (header === null) break
    // Skip events not in DB
    if (EVENTS_TO_SKIP.has(header)) continue
    // Validate header is known (throws if unknown — surfaces typos early)
    mapEventName(header)

    const quali = parsePickList(
      [readCell(ws, rows.qualiRow, col + 0), readCell(ws, rows.qualiRow, col + 1)],
      1
    )
    const sprintQuali = parsePickList(
      [readCell(ws, rows.sprintRow, col + 0)],
      1
    )
    const sprint = parsePickList(
      [
        readCell(ws, rows.sprintRow, col + 2),
        readCell(ws, rows.sprintRow, col + 3),
        readCell(ws, rows.sprintRow, col + 4)
      ],
      1
    )
    const race = parsePickList(
      [0, 1, 2, 3, 4].map((d) => readCell(ws, rows.raceRow, col + d)),
      1
    )
    const excelPoints = {
      quali:  readNumber(ws, rows.qualiRow,  col + 5) ?? 0,
      sprint: readNumber(ws, rows.sprintRow, col + 5) ?? 0,
      race:   readNumber(ws, rows.raceRow,   col + 5) ?? 0
    }
    out[header] = { quali, sprintQuali, sprint, race, excelPoints }
  }
  return out
}
