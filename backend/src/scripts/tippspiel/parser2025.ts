// Season profile: 2025 workbook parser.
//
// Reuses the 2026 layout constants + pure cell-readers (parser.ts) but applies
// the 2025 maps (mappings2025.ts) and two 2025-specific behaviours:
//   - player names are READ from the sheet (the 2025 roster/order differs from
//     2026 and includes Manu/Julius), stopping at the "Korrekt" truth row;
//   - the preseason *standings* columns are matched to players BY NAME, because
//     the 2025 standings block orders Jonas/Merlin opposite to the picks rows —
//     positional indexing would mis-attribute their predicted standings.
import * as XLSX from 'xlsx'
import {
  readCell, readNumber, isSkipMarker,
  RACE_HEADER_ROW, RACE_START_COL, RACE_COLS_EACH,
  STANDINGS_HEADER_ROW, STANDINGS_FIRST_DATA_ROW, STANDINGS_COLS_PER_PLAYER, STANDINGS_FIRST_TEAMS_COL,
  PRESEASON_SINGLE_ROW_START, PLAYER_FIRST_NAME_ROW, PLAYER_ROW_STRIDE,
  PLAYER_QUALI_OFFSET, PLAYER_SPRINT_OFFSET, PLAYER_RACE_OFFSET
} from './parser.js'
import { mapEventName2025, mapDriverCode2025, mapConstructorId2025, EVENTS_TO_SKIP_2025 } from './mappings2025.js'
import { mapPreseasonCategory } from './mappings.js'
import type { RacePicks, ParsedSeason, ParsedPlayer } from './types.js'
import type { PreseasonCategory } from '../../domain/types.js'

type Sheet = XLSX.WorkSheet
const SHEET_NAME = 'Tippspiel 2025'
const NON_PLAYER_ROWS = new Set(['korrekt', 'chatgpt'])
const MAX_PLAYER_SLOTS = 40

const PRESEASON_SINGLE_COLS = [35, 38, 41, 44, 47, 50, 53]

export function parsePickList2025(cells: (string | null)[], startPosition: number): { position: number; driverCode: string }[] {
  // Unlike 2026, a "---" or blank means "no pick at this position" rather than a
  // data error: 2025 players occasionally left a slot empty (e.g. Julius picked
  // only 2 of 3 sprint places). Keep the filled picks at their slot position;
  // the importer skips a session whose count != the expected number of picks.
  const picks: { position: number; driverCode: string }[] = []
  const seen = new Set<string>()
  for (let i = 0; i < cells.length; i++) {
    const cell = cells[i] ?? null
    if (cell === null || isSkipMarker(cell)) continue
    const code = mapDriverCode2025(cell)
    if (seen.has(code)) throw new Error(`duplicate driver in pick list: ${code}`)
    seen.add(code)
    picks.push({ position: startPosition + i, driverCode: code })
  }
  return picks
}

export type PlayerBlockRows = { qualiRow: number; sprintRow: number; raceRow: number }

export function parsePlayerRaceBlock2025(ws: Sheet, rows: PlayerBlockRows): Record<string, RacePicks> {
  const out: Record<string, RacePicks> = {}
  for (let col = RACE_START_COL; ; col += RACE_COLS_EACH) {
    const header = readCell(ws, RACE_HEADER_ROW, col)
    if (header === null) break
    if (EVENTS_TO_SKIP_2025.has(header)) continue
    mapEventName2025(header) // validate header (throws early on typos)

    const quali = parsePickList2025([readCell(ws, rows.qualiRow, col + 0), readCell(ws, rows.qualiRow, col + 1)], 1)
    const sprintQuali = parsePickList2025([readCell(ws, rows.sprintRow, col + 0)], 1)
    const sprint = parsePickList2025(
      [readCell(ws, rows.sprintRow, col + 2), readCell(ws, rows.sprintRow, col + 3), readCell(ws, rows.sprintRow, col + 4)], 1
    )
    const race = parsePickList2025([0, 1, 2, 3, 4].map((d) => readCell(ws, rows.raceRow, col + d)), 1)
    out[header] = {
      quali, sprintQuali, sprint, race,
      excelPoints: {
        quali: readNumber(ws, rows.qualiRow, col + 5) ?? 0,
        sprint: readNumber(ws, rows.sprintRow, col + 5) ?? 0,
        race: readNumber(ws, rows.raceRow, col + 5) ?? 0
      }
    }
  }
  return out
}

export function readPlayerNames2025(ws: Sheet): { name: string; nameRow: number }[] {
  const players: { name: string; nameRow: number }[] = []
  for (let idx = 0; idx < MAX_PLAYER_SLOTS; idx++) {
    const nameRow = PLAYER_FIRST_NAME_ROW + idx * PLAYER_ROW_STRIDE
    const name = readCell(ws, nameRow, 1)
    if (name === null || NON_PLAYER_ROWS.has(name.toLowerCase())) break
    players.push({ name, nameRow })
  }
  return players
}

/** Map player display name -> standings column index (the standings block can
 *  order players differently from the picks rows). */
function standingsIndexByName(ws: Sheet): Map<string, number> {
  const map = new Map<string, number>()
  for (let i = 0; i < MAX_PLAYER_SLOTS; i++) {
    const nameCol = STANDINGS_FIRST_TEAMS_COL + 1 + i * STANDINGS_COLS_PER_PLAYER
    const name = readCell(ws, STANDINGS_HEADER_ROW, nameCol)
    if (name === null) break
    if (NON_PLAYER_ROWS.has(name.toLowerCase())) continue
    map.set(name, i)
  }
  return map
}

/** Map player display name -> preseason single-pick row. */
function preseasonRowByName(ws: Sheet): Map<string, number> {
  const map = new Map<string, number>()
  for (let i = 0; i < MAX_PLAYER_SLOTS; i++) {
    const row = PRESEASON_SINGLE_ROW_START + i
    const name = readCell(ws, row, 1)
    if (name === null) break
    if (NON_PLAYER_ROWS.has(name.toLowerCase())) break
    map.set(name, row)
  }
  return map
}

export function parsePlayerStandings2025(ws: Sheet, standingsIndex: number): {
  constructors: { position: number; constructorId: string }[]
  drivers: { position: number; driverCode: string }[]
} {
  const teamsCol = STANDINGS_FIRST_TEAMS_COL + standingsIndex * STANDINGS_COLS_PER_PLAYER
  const driversCol = teamsCol + 2
  // 2025 has 10 constructors (no Audi/Cadillac) vs 2026's 11, and a variable
  // number of drivers; below the last entity sits a numeric score cell. Stop at
  // the first blank or numeric cell rather than assuming a fixed count.
  const isScoreCell = (s: string) => /^-?\d+(\.\d+)?$/.test(s)
  const constructors: { position: number; constructorId: string }[] = []
  for (let i = 0; i < 11; i++) {
    const cell = readCell(ws, STANDINGS_FIRST_DATA_ROW + i, teamsCol)
    if (cell === null || isScoreCell(cell)) break
    constructors.push({ position: i + 1, constructorId: mapConstructorId2025(cell) })
  }
  const drivers: { position: number; driverCode: string }[] = []
  for (let i = 0; i < 22; i++) {
    const cell = readCell(ws, STANDINGS_FIRST_DATA_ROW + i, driversCol)
    if (cell === null || isScoreCell(cell)) break
    drivers.push({ position: i + 1, driverCode: mapDriverCode2025(cell) })
  }
  return { constructors, drivers }
}

export function parsePlayerPreseasonSingle2025(ws: Sheet, row: number): Partial<Record<PreseasonCategory, {
  driverCode: string | null
  constructorId: string | null
}>> {
  const out: Partial<Record<PreseasonCategory, { driverCode: string | null; constructorId: string | null }>> = {}
  for (const excelCol of PRESEASON_SINGLE_COLS) {
    const label = readCell(ws, 4, excelCol)
    if (label === null) continue
    const category = mapPreseasonCategory(label)
    if (category === null) continue // e.g. "meiste Rennsiege"
    const teamRaw = readCell(ws, row, excelCol)
    const driverRaw = readCell(ws, row, excelCol + 1)
    if (teamRaw === null && driverRaw === null) continue
    out[category] = {
      constructorId: teamRaw ? mapConstructorId2025(teamRaw) : null,
      driverCode: driverRaw ? mapDriverCode2025(driverRaw) : null
    }
  }
  return out
}

export function parseWorkbook2025(wb: XLSX.WorkBook): ParsedSeason {
  const ws = wb.Sheets[SHEET_NAME]
  if (!ws) throw new Error(`sheet "${SHEET_NAME}" not found (have: ${wb.SheetNames.join(', ')})`)

  const pickPlayers = readPlayerNames2025(ws)
  const sIndexByName = standingsIndexByName(ws)
  const psRowByName = preseasonRowByName(ws)

  const players: ParsedPlayer[] = pickPlayers.map(({ name, nameRow }) => {
    const sIndex = sIndexByName.get(name)
    const psRow = psRowByName.get(name)
    return {
      excelName: name,
      racePicks: parsePlayerRaceBlock2025(ws, {
        qualiRow: nameRow + PLAYER_QUALI_OFFSET,
        sprintRow: nameRow + PLAYER_SPRINT_OFFSET,
        raceRow: nameRow + PLAYER_RACE_OFFSET
      }),
      preseasonStandings: sIndex !== undefined
        ? parsePlayerStandings2025(ws, sIndex)
        : { constructors: [], drivers: [] },
      preseasonSingle: psRow !== undefined ? parsePlayerPreseasonSingle2025(ws, psRow) : {}
    }
  })
  return { seasonYear: 2025, players }
}
