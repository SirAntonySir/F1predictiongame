import { describe, it, expect } from 'vitest'
import { readCell, isSkipMarker, parsePickList, RACE_COLS_EACH, RACE_START_COL } from '../../../src/scripts/tippspiel/parser.js'

// Minimal fake sheet shape: { [A1ref]: { v: value } }
function sheet(cells: Record<string, unknown>) {
  const ws: Record<string, { v: unknown }> = {}
  for (const [k, v] of Object.entries(cells)) {
    ws[k] = { v }
  }
  return ws
}

describe('readCell', () => {
  it('returns the trimmed string value', () => {
    expect(readCell(sheet({ 'A1': '  hi  ' }) as any, 1, 1)).toBe('hi')
  })
  it('returns null for missing cell', () => {
    expect(readCell(sheet({}) as any, 5, 7)).toBeNull()
  })
  it('returns null for empty string', () => {
    expect(readCell(sheet({ 'A1': '' }) as any, 1, 1)).toBeNull()
  })
  it('coerces number to string', () => {
    expect(readCell(sheet({ 'B2': 42 }) as any, 2, 2)).toBe('42')
  })
})

describe('isSkipMarker', () => {
  it('detects " ---" patterns', () => {
    expect(isSkipMarker(' ---')).toBe(true)
    expect(isSkipMarker('---')).toBe(true)
    expect(isSkipMarker(' --- ')).toBe(true)
  })
  it('does not match real driver codes', () => {
    expect(isSkipMarker('VER')).toBe(false)
    expect(isSkipMarker('Rus')).toBe(false)
  })
  it('treats null/empty as not-skip (caller handles null separately)', () => {
    expect(isSkipMarker(null)).toBe(false)
    expect(isSkipMarker('')).toBe(false)
  })
})

describe('parsePickList', () => {
  it('returns picks for all non-skip cells, mapped to driver codes', () => {
    const result = parsePickList(['Ver', 'Nor', 'Rus'], 1)
    expect(result).toEqual([
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'NOR' },
      { position: 3, driverCode: 'RUS' }
    ])
  })
  it('returns [] if every cell is null or skip marker (player did not tip)', () => {
    expect(parsePickList([null, null], 1)).toEqual([])
    expect(parsePickList([' ---', ' ---', ' ---'], 1)).toEqual([])
  })
  it('throws if partially filled (some picks present, some missing without " ---")', () => {
    expect(() => parsePickList(['Ver', null], 1)).toThrow(/incomplete pick list/i)
  })
  it('throws on duplicate driver in one pick list', () => {
    expect(() => parsePickList(['Ver', 'Ver'], 1)).toThrow(/duplicate driver/i)
  })
  it('starting position is configurable', () => {
    const r = parsePickList(['Pia', 'Lec'], 4)
    expect(r).toEqual([
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'LEC' }
    ])
  })
})

describe('layout constants', () => {
  it('RACE_START_COL = 3 and RACE_COLS_EACH = 6', () => {
    expect(RACE_START_COL).toBe(3)
    expect(RACE_COLS_EACH).toBe(6)
  })
})

import * as XLSX from 'xlsx'
import { parsePlayerRaceBlock } from '../../../src/scripts/tippspiel/parser.js'

function buildSheetWithRaceHeaders() {
  const ws: Record<string, XLSX.CellObject> = {}
  // Race headers row 68 (sheet index 67), cols 3 (Australia), 9 (China), 15 (Japan)
  ws[XLSX.utils.encode_cell({ r: 67, c: 2 })] = { v: 'Australia', t: 's' } as XLSX.CellObject
  ws[XLSX.utils.encode_cell({ r: 67, c: 8 })] = { v: 'China',     t: 's' } as XLSX.CellObject
  ws[XLSX.utils.encode_cell({ r: 67, c: 14 })] = { v: 'Japan',    t: 's' } as XLSX.CellObject
  return ws
}

describe('parsePlayerRaceBlock', () => {
  it('extracts quali (2), sprintQuali (1), sprint (3), race (5) per race', () => {
    const ws = buildSheetWithRaceHeaders()
    // Quali row r=qualiRow=72 → r index 71
    // Australia quali (cols 3,4): Ver, Nor
    ws[XLSX.utils.encode_cell({ r: 71, c: 2 })] = { v: 'Ver', t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 71, c: 3 })] = { v: 'Nor', t: 's' } as XLSX.CellObject
    // Quali points (col 8)
    ws[XLSX.utils.encode_cell({ r: 71, c: 7 })] = { v: 6, t: 'n' } as XLSX.CellObject
    // Race row r=raceRow=74 → r index 73 — Rus, Ant, Had, Lec, Nor
    const raceDrivers = ['Rus','Ant','Had','Lec','Nor']
    raceDrivers.forEach((d, i) => {
      ws[XLSX.utils.encode_cell({ r: 73, c: 2 + i })] = { v: d, t: 's' } as XLSX.CellObject
    })
    ws[XLSX.utils.encode_cell({ r: 73, c: 7 })] = { v: 13, t: 'n' } as XLSX.CellObject
    // China: sprint shootout col 9 (idx 8), sprint race cols 11,12,13 (idx 10,11,12)
    ws[XLSX.utils.encode_cell({ r: 72, c: 8 })]  = { v: 'Rus', t: 's' } as XLSX.CellObject  // sprintQuali
    ws[XLSX.utils.encode_cell({ r: 72, c: 10 })] = { v: 'Ver', t: 's' } as XLSX.CellObject  // sprint P1
    ws[XLSX.utils.encode_cell({ r: 72, c: 11 })] = { v: 'Ant', t: 's' } as XLSX.CellObject  // sprint P2
    ws[XLSX.utils.encode_cell({ r: 72, c: 12 })] = { v: 'Nor', t: 's' } as XLSX.CellObject  // sprint P3
    ws[XLSX.utils.encode_cell({ r: 72, c: 13 })] = { v: 5, t: 'n' } as XLSX.CellObject       // points

    const result = parsePlayerRaceBlock(ws as any, { qualiRow: 72, sprintRow: 73, raceRow: 74 })

    expect(result['Australia'].quali).toEqual([
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'NOR' }
    ])
    expect(result['Australia'].race).toEqual([
      { position: 1, driverCode: 'RUS' },
      { position: 2, driverCode: 'ANT' },
      { position: 3, driverCode: 'HAD' },
      { position: 4, driverCode: 'LEC' },
      { position: 5, driverCode: 'NOR' }
    ])
    expect(result['Australia'].sprint).toEqual([])
    expect(result['Australia'].sprintQuali).toEqual([])
    expect(result['Australia'].excelPoints).toEqual({ quali: 6, sprint: 0, race: 13 })

    expect(result['China'].sprintQuali).toEqual([{ position: 1, driverCode: 'RUS' }])
    expect(result['China'].sprint).toEqual([
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'ANT' },
      { position: 3, driverCode: 'NOR' }
    ])
    expect(result['China'].excelPoints.sprint).toBe(5)

    // Japan has no cells: every list empty, points zero
    expect(result['Japan']).toBeDefined()
    expect(result['Japan'].quali).toEqual([])
    expect(result['Japan'].race).toEqual([])
    expect(result['Japan'].excelPoints).toEqual({ quali: 0, sprint: 0, race: 0 })
  })

  it('skips events present in EVENTS_TO_SKIP (e.g. Bahrain)', () => {
    const ws = buildSheetWithRaceHeaders()
    ws[XLSX.utils.encode_cell({ r: 67, c: 20 })] = { v: 'Bahrain', t: 's' } as XLSX.CellObject
    // Bahrain quali col 21 (idx 20) — should be ignored
    ws[XLSX.utils.encode_cell({ r: 71, c: 20 })] = { v: 'Ver', t: 's' } as XLSX.CellObject
    const result = parsePlayerRaceBlock(ws as any, { qualiRow: 72, sprintRow: 73, raceRow: 74 })
    expect(result['Bahrain']).toBeUndefined()
    expect(result['Australian Grand Prix']).toBeUndefined()  // keys are the *Excel* race header
    expect(Object.keys(result)).toContain('Australia')
  })
})

import { parsePlayerStandings, parsePlayerPreseasonSingle, parseWorkbook } from '../../../src/scripts/tippspiel/parser.js'

describe('parsePlayerStandings', () => {
  it('reads 11 constructor and 22 driver positions for a given player column', () => {
    const ws: Record<string, XLSX.CellObject> = {}
    // For player index 0 (Jan): teams col = 3, drivers col = 5
    const teams = ['McLaren','Merc','Ferrari','RedBull','Alpine','Haas','Vcarb','Audi','Williams','Cadillac','Aston']
    teams.forEach((t, i) => {
      ws[XLSX.utils.encode_cell({ r: 33 - 1 + i, c: 2 })] = { v: t, t: 's' } as XLSX.CellObject
    })
    const drivers = ['Ver','Nor','Rus','Pia','Lec','Had','Ant','Ham','Gas','Bea','Oco','Lin','Alb','Bor','Col','Law','Hul','Sai','Bot','Per','Alo','Str']
    drivers.forEach((d, i) => {
      ws[XLSX.utils.encode_cell({ r: 33 - 1 + i, c: 4 })] = { v: d, t: 's' } as XLSX.CellObject
    })
    const result = parsePlayerStandings(ws as any, 0)
    expect(result.constructors).toHaveLength(11)
    expect(result.constructors[0]).toEqual({ position: 1, constructorId: 'mclaren' })
    expect(result.constructors[10]).toEqual({ position: 11, constructorId: 'aston_martin' })
    expect(result.drivers).toHaveLength(22)
    expect(result.drivers[0]).toEqual({ position: 1, driverCode: 'VER' })
    expect(result.drivers[21]).toEqual({ position: 22, driverCode: 'STR' })
  })

  it('throws if any standings cell is missing', () => {
    const ws: Record<string, XLSX.CellObject> = {}
    // teams 1..10 only, missing pos 11
    const teams = ['McLaren','Merc','Ferrari','RedBull','Alpine','Haas','Vcarb','Audi','Williams','Cadillac']
    teams.forEach((t, i) => {
      ws[XLSX.utils.encode_cell({ r: 33 - 1 + i, c: 2 })] = { v: t, t: 's' } as XLSX.CellObject
    })
    expect(() => parsePlayerStandings(ws as any, 0)).toThrow(/missing constructor standings/i)
  })
})

describe('parsePlayerPreseasonSingle', () => {
  it('reads the 6 supported categories for the given player row', () => {
    const ws: Record<string, XLSX.CellObject> = {}
    // Player row for Jan = PRESEASON_SINGLE_ROW_START + 0 = 7 (sheet idx 6)
    // Need category labels in row 4 (sheet idx 3) at the respective cols
    ws[XLSX.utils.encode_cell({ r: 3, c: 34 })] = { v: 'größte Enttäuschung',  t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 3, c: 37 })] = { v: 'größte Überraschung',  t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 3, c: 40 })] = { v: 'meiste DNFs',          t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 3, c: 43 })] = { v: 'meiste Poles',         t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 3, c: 46 })] = { v: 'meiste fastest laps',  t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 3, c: 49 })] = { v: 'meiste Rennsiege',     t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 3, c: 52 })] = { v: 'Champions',            t: 's' } as XLSX.CellObject

    // Disappointment team col 35 (idx 34), driver col 36 (idx 35)
    ws[XLSX.utils.encode_cell({ r: 6, c: 34 })] = { v: 'Williams', t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 6, c: 35 })] = { v: 'Sai',      t: 's' } as XLSX.CellObject
    // Surprise team col 38 (idx 37), driver col 39 (idx 38)
    ws[XLSX.utils.encode_cell({ r: 6, c: 37 })] = { v: 'Alpine', t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 6, c: 38 })] = { v: 'Bea',    t: 's' } as XLSX.CellObject
    // Champions WCC col 53 (idx 52), WDC col 54 (idx 53)
    ws[XLSX.utils.encode_cell({ r: 6, c: 52 })] = { v: 'McLaren', t: 's' } as XLSX.CellObject
    ws[XLSX.utils.encode_cell({ r: 6, c: 53 })] = { v: 'Ver',     t: 's' } as XLSX.CellObject

    const result = parsePlayerPreseasonSingle(ws as any, 0)
    expect(result.disappointment).toEqual({ constructorId: 'williams', driverCode: 'SAI' })
    expect(result.surprise).toEqual({ constructorId: 'alpine', driverCode: 'BEA' })
    expect(result.wdc_wcc).toEqual({ constructorId: 'mclaren', driverCode: 'VER' })
    expect(result.dnf).toBeUndefined()
  })
})

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

describe('parseWorkbook (integration with real Tippspiel.xlsx if present)', () => {
  const candidatePath = path.join(os.homedir(), 'Downloads', 'Tippspiel.xlsx')
  const exists = fs.existsSync(candidatePath)

  it.skipIf(!exists)('returns 11 players with at least Australia race picks', () => {
    const wb = XLSX.readFile(candidatePath)
    const parsed = parseWorkbook(wb, 2026)
    expect(parsed.seasonYear).toBe(2026)
    expect(parsed.players).toHaveLength(11)
    const jan = parsed.players.find((p) => p.excelName === 'Jan')!
    expect(jan).toBeDefined()
    expect(jan.racePicks['Australia'].race).toHaveLength(5)
    expect(jan.preseasonStandings.constructors).toHaveLength(11)
    expect(jan.preseasonStandings.drivers).toHaveLength(22)
  })
})

function buildMinimalWorkbook(): XLSX.WorkBook {
  // Build a workbook with one sheet that has just enough cells for parseWorkbook
  // not to throw and to produce empty pick blocks for all 11 players.
  const ws: Record<string, XLSX.CellObject> = {}
  // Race header row 68 (sheet idx 67) — Australia at col 3
  ws[XLSX.utils.encode_cell({ r: 67, c: 2 })] = { v: 'Australia', t: 's' } as XLSX.CellObject
  // Preseason single-category label row 4 cols 35,38,41,44,47,50,53 (indices 34..52)
  const labels: Record<number, string> = {
    34: 'größte Enttäuschung',
    37: 'größte Überraschung',
    40: 'meiste DNFs',
    43: 'meiste Poles',
    46: 'meiste fastest laps',
    49: 'meiste Rennsiege',
    52: 'Champions'
  }
  for (const [c, v] of Object.entries(labels)) {
    ws[XLSX.utils.encode_cell({ r: 3, c: Number(c) })] = { v, t: 's' } as XLSX.CellObject
  }
  // Standings: all 11 players, 11 constructors, 22 drivers, default values
  const teams = ['McLaren','Merc','Ferrari','RedBull','Alpine','Haas','Vcarb','Audi','Williams','Cadillac','Aston']
  const drivers = ['Ver','Nor','Rus','Pia','Lec','Had','Ant','Ham','Gas','Bea','Oco','Lin','Alb','Bor','Col','Law','Hul','Sai','Bot','Per','Alo','Str']
  for (let p = 0; p < 11; p++) {
    const teamsCol = 2 + p * 4
    const driversCol = teamsCol + 2
    teams.forEach((t, i)   => ws[XLSX.utils.encode_cell({ r: 32 + i, c: teamsCol })]   = { v: t, t: 's' } as XLSX.CellObject)
    drivers.forEach((d, i) => ws[XLSX.utils.encode_cell({ r: 32 + i, c: driversCol })] = { v: d, t: 's' } as XLSX.CellObject)
  }
  const sheet = ws as XLSX.WorkSheet
  ;(sheet as any)['!ref'] = 'A1:EQ151'
  return { SheetNames: ['Tippspiel 2026'], Sheets: { 'Tippspiel 2026': sheet } } as XLSX.WorkBook
}

describe('parseWorkbook (in-memory)', () => {
  it('parses 11 players with empty race picks and full standings', () => {
    const parsed = parseWorkbook(buildMinimalWorkbook(), 2026)
    expect(parsed.players.map((p) => p.excelName)).toEqual([
      'Jan','Lukas','Jakob','Simon','Juli','Jonas','Janine','Jana','Anton','David','Merlin'
    ])
    const jan = parsed.players[0]
    expect(jan.racePicks['Australia'].quali).toEqual([])
    expect(jan.racePicks['Australia'].race).toEqual([])
    expect(jan.preseasonStandings.constructors).toHaveLength(11)
    expect(jan.preseasonStandings.drivers).toHaveLength(22)
  })

  it('throws when sheet "Tippspiel YYYY" is missing', () => {
    const empty = { SheetNames: ['Other'], Sheets: { Other: {} as any } } as XLSX.WorkBook
    expect(() => parseWorkbook(empty, 2026)).toThrow(/sheet.*Tippspiel 2026/i)
  })
})
