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
