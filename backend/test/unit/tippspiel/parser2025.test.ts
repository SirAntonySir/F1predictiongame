import { describe, it, expect } from 'vitest'
import * as XLSX from 'xlsx'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {
  readPlayerNames2025,
  parsePlayerRaceBlock2025,
  parsePickList2025,
  parseWorkbook2025
} from '../../../src/scripts/tippspiel/parser2025.js'

describe('parsePickList2025', () => {
  it('returns only the filled picks, treating --- and blanks as no-pick (not an error)', () => {
    // Julius/Belgium sprint: picked P1+P2, explicitly skipped P3 with "---"
    expect(parsePickList2025(['Pia', 'Ver', '---'], 1)).toEqual([
      { position: 1, driverCode: 'PIA' },
      { position: 2, driverCode: 'VER' }
    ])
  })
  it('returns [] when fully empty or all skip markers', () => {
    expect(parsePickList2025([null, null], 1)).toEqual([])
    expect(parsePickList2025(['---', '---', '---'], 1)).toEqual([])
  })
  it('still throws on a duplicate driver', () => {
    expect(() => parsePickList2025(['Ver', 'Ver'], 1)).toThrow(/duplicate/i)
  })
})

const cell = (r: number, c: number, v: unknown, t: 's' | 'n' = 's') =>
  [XLSX.utils.encode_cell({ r: r - 1, c: c - 1 }), { v, t }] as const

function makeSheet(entries: (readonly [string, { v: unknown; t: string }])[]): XLSX.WorkSheet {
  const ws: Record<string, unknown> = {}
  for (const [ref, obj] of entries) ws[ref] = obj
  return ws as XLSX.WorkSheet
}

describe('readPlayerNames2025', () => {
  it('reads the 12 players from the sheet and stops at the Korrekt row', () => {
    const names = ['Jan', 'Lukas', 'Jakob', 'David', 'Simon', 'Manu', 'Julius', 'Merlin', 'Jonas', 'Jana', 'Janine', 'Anton']
    const entries = names.map((n, i) => cell(70 + i * 7, 1, n))
    // Korrekt truth row sits where player #13 would be (row 154) — must be excluded.
    entries.push(cell(154, 1, 'Korrekt'))
    const players = readPlayerNames2025(makeSheet(entries))
    expect(players.map((p) => p.name)).toEqual(names)
    expect(players[0]).toEqual({ name: 'Jan', nameRow: 70 })
    expect(players[11]).toEqual({ name: 'Anton', nameRow: 147 })
  })

  it('stops at the first empty name slot', () => {
    const entries = [cell(70, 1, 'Jan'), cell(77, 1, 'Lukas')] // row 84 empty
    const players = readPlayerNames2025(makeSheet(entries))
    expect(players.map((p) => p.name)).toEqual(['Jan', 'Lukas'])
  })
})

describe('parsePlayerRaceBlock2025', () => {
  it('parses quali/race keyed by the 2025 Excel header and does NOT skip Bahrain', () => {
    const entries = [
      cell(68, 3, 'Australien'),
      cell(68, 9, 'Bahrain'),
      // Australien quali (cols 3,4) + points col 8
      cell(72, 3, 'Nor'), cell(72, 4, 'Lec'), cell(72, 8, 4, 'n'),
      // Australien race (cols 3..7) + points col 8
      cell(74, 3, 'Nor'), cell(74, 4, 'Pia'), cell(74, 5, 'Ver'), cell(74, 6, 'Rus'), cell(74, 7, 'Lec'), cell(74, 8, 7, 'n'),
      // Bahrain quali (cols 9,10)
      cell(72, 9, 'Pia'), cell(72, 10, 'Nor'), cell(72, 14, 4, 'n')
    ]
    const result = parsePlayerRaceBlock2025(makeSheet(entries), { qualiRow: 72, sprintRow: 73, raceRow: 74 })

    expect(result['Australien'].quali).toEqual([
      { position: 1, driverCode: 'NOR' },
      { position: 2, driverCode: 'LEC' }
    ])
    expect(result['Australien'].race).toEqual([
      { position: 1, driverCode: 'NOR' },
      { position: 2, driverCode: 'PIA' },
      { position: 3, driverCode: 'VER' },
      { position: 4, driverCode: 'RUS' },
      { position: 5, driverCode: 'LEC' }
    ])
    expect(result['Australien'].excelPoints).toEqual({ quali: 4, sprint: 0, race: 7 })
    // Bahrain is NOT skipped in 2025
    expect(result['Bahrain']).toBeDefined()
    expect(result['Bahrain'].quali).toEqual([
      { position: 1, driverCode: 'PIA' },
      { position: 2, driverCode: 'NOR' }
    ])
  })

  it('maps 2025-only driver codes (Doh -> DOO, Tsu -> TSU)', () => {
    const entries = [
      cell(68, 3, 'Brasil'),
      cell(74, 3, 'Nor'), cell(74, 4, 'Doh'), cell(74, 5, 'Tsu'), cell(74, 6, 'Rus'), cell(74, 7, 'Bae')
    ]
    const result = parsePlayerRaceBlock2025(makeSheet(entries), { qualiRow: 72, sprintRow: 73, raceRow: 74 })
    expect(result['Brasil'].race.map((p) => p.driverCode)).toEqual(['NOR', 'DOO', 'TSU', 'RUS', 'BEA'])
  })
})

describe('parseWorkbook2025 (real Tippspiel-25.xlsx if present)', () => {
  const candidate = path.join(os.homedir(), 'Downloads', 'Tippspiel-25.xlsx')
  const exists = fs.existsSync(candidate)

  it.skipIf(!exists)('returns the 12 players (no Korrekt/ChatGPT) with 2025 picks + standings', () => {
    const wb = XLSX.readFile(candidate)
    const parsed = parseWorkbook2025(wb)
    expect(parsed.seasonYear).toBe(2025)
    expect(parsed.players.map((p) => p.excelName)).toEqual([
      'Jan', 'Lukas', 'Jakob', 'David', 'Simon', 'Manu', 'Julius', 'Merlin', 'Jonas', 'Jana', 'Janine', 'Anton'
    ])
    const jan = parsed.players[0]!
    expect(jan.racePicks['Australien']!.race).toHaveLength(5)
    expect(jan.racePicks['Bahrain']).toBeDefined() // not skipped
    expect(jan.preseasonStandings.constructors).toHaveLength(10) // 2025 has 10 teams
    expect(jan.preseasonStandings.drivers.length).toBeGreaterThan(0)
    // every player resolved to a standings column (name-based mapping handles the Jonas/Merlin swap)
    for (const p of parsed.players) {
      expect(p.preseasonStandings.constructors.length).toBeGreaterThanOrEqual(10)
    }
  })
})
