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
  // Race headers row 4, cols 3 (Australia), 9 (China), 15 (Japan)
  ws[XLSX.utils.encode_cell({ r: 3, c: 2 })] = { v: 'Australia', t: 's' } as XLSX.CellObject
  ws[XLSX.utils.encode_cell({ r: 3, c: 8 })] = { v: 'China',     t: 's' } as XLSX.CellObject
  ws[XLSX.utils.encode_cell({ r: 3, c: 14 })] = { v: 'Japan',    t: 's' } as XLSX.CellObject
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
    ws[XLSX.utils.encode_cell({ r: 3, c: 20 })] = { v: 'Bahrain', t: 's' } as XLSX.CellObject
    // Bahrain quali col 21 (idx 20) — should be ignored
    ws[XLSX.utils.encode_cell({ r: 71, c: 20 })] = { v: 'Ver', t: 's' } as XLSX.CellObject
    const result = parsePlayerRaceBlock(ws as any, { qualiRow: 72, sprintRow: 73, raceRow: 74 })
    expect(result['Bahrain']).toBeUndefined()
    expect(result['Australian Grand Prix']).toBeUndefined()  // keys are the *Excel* race header
    expect(Object.keys(result)).toContain('Australia')
  })
})
