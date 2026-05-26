# Tippspiel Excel Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A TypeScript dev script that imports the running season's tips from `Tippspiel.xlsx` into the backend database and prints a side-by-side comparison of Excel-computed points vs. App-computed points so the scoring engine can be validated.

**Architecture:** Pure parser → in-memory `ParsedSeason` → repo-based importer → existing `rescoreSession` → validator that diffs Excel points vs. `score.points_total`. Idempotent (upsert everywhere). Layout constants for the spreadsheet are hard-coded; mapping dicts (driver, constructor, event, category) live in their own module.

**Tech Stack:** Node 22+, TypeScript, Drizzle ORM, Postgres, Vitest, `xlsx` (SheetJS) as devDependency. Existing repos (`backend/src/repo/*`) and `rescoreSession` from `backend/src/scoring/rescorer.ts`.

**Spec:** `docs/superpowers/specs/2026-05-26-tippspiel-excel-import-design.md`

---

## File Structure

**New files:**
- `backend/src/scripts/tippspiel/types.ts` — `ParsedSeason`, `ParsedPlayer`, `ParsedRacePicks`
- `backend/src/scripts/tippspiel/mappings.ts` — driver/constructor/event/category dicts + lookup helpers
- `backend/src/scripts/tippspiel/parser.ts` — xlsx workbook → `ParsedSeason`
- `backend/src/scripts/tippspiel/importer.ts` — `ParsedSeason` → DB (users, league, predictions, preseason)
- `backend/src/scripts/tippspiel/validator.ts` — read scores, build & print comparison table
- `backend/src/scripts/importTippspiel.ts` — CLI entry: parse args, run parser → importer → rescore → validator
- `backend/test/unit/tippspiel/mappings.test.ts`
- `backend/test/unit/tippspiel/parser.test.ts`
- `backend/test/unit/tippspiel/validator.test.ts`

**Modified files:**
- `backend/package.json` — add `xlsx` devDependency + `import:tippspiel` script

---

## Task 1: Add `xlsx` devDependency and npm script

**Files:**
- Modify: `backend/package.json`

- [ ] **Step 1: Install xlsx as devDependency**

Run: `cd backend && npm install --save-dev xlsx@0.18.5`
Expected: exits 0, `xlsx` appears under `devDependencies` in `package.json`.

- [ ] **Step 2: Add npm run script**

Edit `backend/package.json`, inside the `"scripts"` block, append after `"test:watch": "vitest"`:

```json
    "import:tippspiel": "tsx src/scripts/importTippspiel.ts"
```

(Don't forget the comma after the preceding line.)

- [ ] **Step 3: Verify**

Run: `cd backend && npm run import:tippspiel -- --help 2>&1 || true`
Expected: error like `Cannot find module '.../scripts/importTippspiel.ts'` (file doesn't exist yet) — that's fine, it confirms the npm script is wired.

- [ ] **Step 4: Commit**

```bash
git add backend/package.json backend/package-lock.json
git commit -m "chore: add xlsx devDependency for tippspiel import script"
```

---

## Task 2: Define parsed-data types

**Files:**
- Create: `backend/src/scripts/tippspiel/types.ts`

- [ ] **Step 1: Write the types file**

```ts
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
```

- [ ] **Step 2: Verify it compiles**

Run: `cd backend && npx tsc --noEmit -p tsconfig.json`
Expected: no new errors related to this file.

- [ ] **Step 3: Commit**

```bash
git add backend/src/scripts/tippspiel/types.ts
git commit -m "feat(tippspiel): parsed-data types"
```

---

## Task 3: Mapping dicts and lookup helpers — failing tests first

**Files:**
- Create: `backend/test/unit/tippspiel/mappings.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
import { describe, it, expect } from 'vitest'
import {
  mapDriverCode,
  mapConstructorId,
  mapEventName,
  mapPreseasonCategory,
  EVENTS_TO_SKIP,
  CATEGORIES_TO_SKIP
} from '../../../src/scripts/tippspiel/mappings.js'

describe('mapDriverCode', () => {
  it('uppercases standard 3-letter codes', () => {
    expect(mapDriverCode('Ver')).toBe('VER')
    expect(mapDriverCode('rus')).toBe('RUS')
    expect(mapDriverCode('PIA')).toBe('PIA')
  })

  it('maps the "Hulk" alias to HUL', () => {
    expect(mapDriverCode('Hulk')).toBe('HUL')
    expect(mapDriverCode('HULK')).toBe('HUL')
  })

  it('throws on unknown driver code', () => {
    expect(() => mapDriverCode('Xyz')).toThrow(/unknown driver code/i)
  })

  it('trims whitespace', () => {
    expect(mapDriverCode(' Ver ')).toBe('VER')
  })
})

describe('mapConstructorId', () => {
  it('maps every Excel constructor label', () => {
    expect(mapConstructorId('McLaren')).toBe('mclaren')
    expect(mapConstructorId('Merc')).toBe('mercedes')
    expect(mapConstructorId('Ferrari')).toBe('ferrari')
    expect(mapConstructorId('RedBull')).toBe('red_bull')
    expect(mapConstructorId('Alpine')).toBe('alpine')
    expect(mapConstructorId('Haas')).toBe('haas')
    expect(mapConstructorId('Vcarb')).toBe('rb')
    expect(mapConstructorId('Audi')).toBe('audi')
    expect(mapConstructorId('Williams')).toBe('williams')
    expect(mapConstructorId('Cadillac')).toBe('cadillac')
    expect(mapConstructorId('Aston')).toBe('aston_martin')
    expect(mapConstructorId('Aston Martin')).toBe('aston_martin')
  })

  it('throws on unknown constructor', () => {
    expect(() => mapConstructorId('Honda')).toThrow(/unknown constructor/i)
  })
})

describe('mapEventName', () => {
  it('maps each Excel race header to DB event name', () => {
    expect(mapEventName('Australia')).toBe('Australian Grand Prix')
    expect(mapEventName('Kanada')).toBe('Canadian Grand Prix')
    expect(mapEventName('Österreich')).toBe('Austrian Grand Prix')
    expect(mapEventName('GB')).toBe('British Grand Prix')
    expect(mapEventName('Niederlande')).toBe('Dutch Grand Prix')
    expect(mapEventName('Mexiko')).toBe('Mexico City Grand Prix')
    expect(mapEventName('Abu Dhabi')).toBe('Abu Dhabi Grand Prix')
  })

  it('returns null for events that should be skipped (not in DB)', () => {
    expect(mapEventName('Bahrain')).toBeNull()
    expect(mapEventName('Saudi')).toBeNull()
    expect(EVENTS_TO_SKIP).toContain('Bahrain')
    expect(EVENTS_TO_SKIP).toContain('Saudi')
  })

  it('throws on unknown event', () => {
    expect(() => mapEventName('Mars')).toThrow(/unknown event/i)
  })
})

describe('mapPreseasonCategory', () => {
  it('maps each DE label to enum value', () => {
    expect(mapPreseasonCategory('größte Enttäuschung')).toBe('disappointment')
    expect(mapPreseasonCategory('größte Überraschung')).toBe('surprise')
    expect(mapPreseasonCategory('meiste DNFs')).toBe('dnf')
    expect(mapPreseasonCategory('meiste Poles')).toBe('poles')
    expect(mapPreseasonCategory('meiste fastest laps')).toBe('fastest_lap')
    expect(mapPreseasonCategory('Champions')).toBe('wdc_wcc')
  })

  it('returns null for unsupported categories', () => {
    expect(mapPreseasonCategory('meiste Rennsiege')).toBeNull()
    expect(CATEGORIES_TO_SKIP).toContain('meiste Rennsiege')
  })

  it('throws on unknown category', () => {
    expect(() => mapPreseasonCategory('zufällige Kategorie')).toThrow(/unknown preseason category/i)
  })
})
```

- [ ] **Step 2: Run tests, confirm failure**

Run: `cd backend && npx vitest run test/unit/tippspiel/mappings.test.ts`
Expected: all tests FAIL because `../../../src/scripts/tippspiel/mappings.js` does not exist.

- [ ] **Step 3: Create mappings module**

Create `backend/src/scripts/tippspiel/mappings.ts`:

```ts
import type { PreseasonCategory } from '../../domain/types.js'

const DRIVER_ALIAS_OVERRIDES: Record<string, string> = {
  HULK: 'HUL'
}

export const KNOWN_DRIVER_CODES = new Set([
  'ALB','ALO','ANT','BEA','BOR','BOT','COL','GAS','HAD','HAM',
  'HUL','LAW','LEC','LIN','NOR','OCO','PER','PIA','RUS','SAI','STR','VER'
])

export function mapDriverCode(raw: string): string {
  const upper = raw.trim().toUpperCase()
  const canonical = DRIVER_ALIAS_OVERRIDES[upper] ?? upper
  if (!KNOWN_DRIVER_CODES.has(canonical)) {
    throw new Error(`unknown driver code: "${raw}" (canonical: "${canonical}")`)
  }
  return canonical
}

const CONSTRUCTOR_MAP: Record<string, string> = {
  'McLaren':      'mclaren',
  'Merc':         'mercedes',
  'Mercedes':     'mercedes',
  'Ferrari':      'ferrari',
  'RedBull':      'red_bull',
  'Red Bull':     'red_bull',
  'Alpine':       'alpine',
  'Haas':         'haas',
  'Vcarb':        'rb',
  'Audi':         'audi',
  'Williams':     'williams',
  'Cadillac':     'cadillac',
  'Aston':        'aston_martin',
  'Aston Martin': 'aston_martin'
}

export function mapConstructorId(raw: string): string {
  const trimmed = raw.trim()
  const id = CONSTRUCTOR_MAP[trimmed]
  if (!id) throw new Error(`unknown constructor: "${raw}"`)
  return id
}

export const EVENTS_TO_SKIP: ReadonlySet<string> = new Set(['Bahrain', 'Saudi'])

const EVENT_MAP: Record<string, string> = {
  'Australia':   'Australian Grand Prix',
  'China':       'Chinese Grand Prix',
  'Japan':       'Japanese Grand Prix',
  'Miami':       'Miami Grand Prix',
  'Kanada':      'Canadian Grand Prix',
  'Monaco':      'Monaco Grand Prix',
  'Barcelona':   'Barcelona Grand Prix',
  'Österreich':  'Austrian Grand Prix',
  'GB':          'British Grand Prix',
  'Belgien':     'Belgian Grand Prix',
  'Ungarn':      'Hungarian Grand Prix',
  'Niederlande': 'Dutch Grand Prix',
  'Italien':     'Italian Grand Prix',
  'Spanien':     'Spanish Grand Prix',
  'Baku':        'Azerbaijan Grand Prix',
  'Singapur':    'Singapore Grand Prix',
  'USA':         'United States Grand Prix',
  'Mexiko':      'Mexico City Grand Prix',
  'Brasilien':   'Brazilian Grand Prix',
  'Las Vegas':   'Las Vegas Grand Prix',
  'Katar':       'Qatar Grand Prix',
  'Abu Dhabi':   'Abu Dhabi Grand Prix'
}

export function mapEventName(raw: string): string | null {
  const trimmed = raw.trim()
  if (EVENTS_TO_SKIP.has(trimmed)) return null
  const name = EVENT_MAP[trimmed]
  if (!name) throw new Error(`unknown event: "${raw}"`)
  return name
}

export const CATEGORIES_TO_SKIP: ReadonlySet<string> = new Set(['meiste Rennsiege'])

const CATEGORY_MAP: Record<string, PreseasonCategory> = {
  'größte Enttäuschung':  'disappointment',
  'größte Überraschung':  'surprise',
  'meiste DNFs':          'dnf',
  'meiste Poles':         'poles',
  'meiste fastest laps':  'fastest_lap',
  'Champions':            'wdc_wcc'
}

export function mapPreseasonCategory(raw: string): PreseasonCategory | null {
  const trimmed = raw.trim()
  if (CATEGORIES_TO_SKIP.has(trimmed)) return null
  const cat = CATEGORY_MAP[trimmed]
  if (!cat) throw new Error(`unknown preseason category: "${raw}"`)
  return cat
}
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `cd backend && npx vitest run test/unit/tippspiel/mappings.test.ts`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scripts/tippspiel/mappings.ts backend/test/unit/tippspiel/mappings.test.ts
git commit -m "feat(tippspiel): driver/constructor/event/category mappings"
```

---

## Task 4: Excel parser — cell-reading helper + skip rule tests

**Files:**
- Create: `backend/test/unit/tippspiel/parser.test.ts`
- Create: `backend/src/scripts/tippspiel/parser.ts`

- [ ] **Step 1: Write failing tests for cell-reading helpers**

```ts
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
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts`
Expected: all tests FAIL (module does not exist).

- [ ] **Step 3: Create parser module — helpers only (no parseWorkbook yet)**

Create `backend/src/scripts/tippspiel/parser.ts`:

```ts
import * as XLSX from 'xlsx'
import { mapDriverCode } from './mappings.js'

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
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scripts/tippspiel/parser.ts backend/test/unit/tippspiel/parser.test.ts
git commit -m "feat(tippspiel): xlsx cell readers + pick list parser"
```

---

## Task 5: Parser — parse a single player's race block

**Files:**
- Modify: `backend/test/unit/tippspiel/parser.test.ts`
- Modify: `backend/src/scripts/tippspiel/parser.ts`

- [ ] **Step 1: Add failing test for `parsePlayerRaceBlock`**

Append to `backend/test/unit/tippspiel/parser.test.ts`:

```ts
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
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts -t parsePlayerRaceBlock`
Expected: FAIL — `parsePlayerRaceBlock` does not exist.

- [ ] **Step 3: Implement `parsePlayerRaceBlock`**

Append to `backend/src/scripts/tippspiel/parser.ts`:

```ts
import { mapEventName, EVENTS_TO_SKIP } from './mappings.js'
import type { RacePicks } from './types.js'

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
      [0,1,2,3,4].map((d) => readCell(ws, rows.raceRow, col + d)),
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
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scripts/tippspiel/parser.ts backend/test/unit/tippspiel/parser.test.ts
git commit -m "feat(tippspiel): parse per-player race block"
```

---

## Task 6: Parser — preseason standings & single-pick categories

**Files:**
- Modify: `backend/test/unit/tippspiel/parser.test.ts`
- Modify: `backend/src/scripts/tippspiel/parser.ts`

- [ ] **Step 1: Add failing tests for `parsePlayerStandings` and `parsePlayerPreseasonSingle`**

Append to `backend/test/unit/tippspiel/parser.test.ts`:

```ts
import { parsePlayerStandings, parsePlayerPreseasonSingle } from '../../../src/scripts/tippspiel/parser.js'

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
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts`
Expected: new tests FAIL (functions don't exist).

- [ ] **Step 3: Implement both functions**

Append to `backend/src/scripts/tippspiel/parser.ts`:

```ts
import { mapConstructorId, mapPreseasonCategory } from './mappings.js'
import type { PreseasonCategory } from '../../domain/types.js'

const PRESEASON_SINGLE_COLS: { excelCol: number }[] = [
  { excelCol: 35 }, // größte Enttäuschung
  { excelCol: 38 }, // größte Überraschung
  { excelCol: 41 }, // meiste DNFs
  { excelCol: 44 }, // meiste Poles
  { excelCol: 47 }, // meiste fastest laps
  { excelCol: 50 }, // meiste Rennsiege  (skipped via category map)
  { excelCol: 53 }  // Champions
]

export function parsePlayerStandings(ws: Sheet, playerIndex: number): {
  constructors: { position: number; constructorId: string }[]
  drivers: { position: number; driverCode: string }[]
} {
  const teamsCol   = STANDINGS_FIRST_TEAMS_COL + playerIndex * STANDINGS_COLS_PER_PLAYER
  const driversCol = teamsCol + 2
  const constructors: { position: number; constructorId: string }[] = []
  for (let i = 0; i < 11; i++) {
    const cell = readCell(ws, STANDINGS_FIRST_DATA_ROW + i, teamsCol)
    if (cell === null) throw new Error(`missing constructor standings at position ${i + 1} (player index ${playerIndex})`)
    constructors.push({ position: i + 1, constructorId: mapConstructorId(cell) })
  }
  const drivers: { position: number; driverCode: string }[] = []
  for (let i = 0; i < 22; i++) {
    const cell = readCell(ws, STANDINGS_FIRST_DATA_ROW + i, driversCol)
    if (cell === null) throw new Error(`missing driver standings at position ${i + 1} (player index ${playerIndex})`)
    drivers.push({ position: i + 1, driverCode: mapDriverCode(cell) })
  }
  return { constructors, drivers }
}

export function parsePlayerPreseasonSingle(ws: Sheet, playerIndex: number): Partial<Record<PreseasonCategory, {
  driverCode: string | null
  constructorId: string | null
}>> {
  const row = PRESEASON_SINGLE_ROW_START + playerIndex
  const out: Partial<Record<PreseasonCategory, { driverCode: string | null; constructorId: string | null }>> = {}
  for (const { excelCol } of PRESEASON_SINGLE_COLS) {
    // Category label sits in row 4 at this column. Use it for category mapping.
    const label = readCell(ws, 4, excelCol)
    if (label === null) continue
    const category = mapPreseasonCategory(label)
    if (category === null) continue  // e.g. "meiste Rennsiege"

    const teamRaw   = readCell(ws, row, excelCol)
    const driverRaw = readCell(ws, row, excelCol + 1)
    if (teamRaw === null && driverRaw === null) continue
    out[category] = {
      constructorId: teamRaw   ? mapConstructorId(teamRaw)   : null,
      driverCode:    driverRaw ? mapDriverCode(driverRaw)    : null
    }
  }
  return out
}
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scripts/tippspiel/parser.ts backend/test/unit/tippspiel/parser.test.ts
git commit -m "feat(tippspiel): parse preseason standings and single-pick categories"
```

---

## Task 7: Parser — top-level `parseWorkbook`

**Files:**
- Modify: `backend/test/unit/tippspiel/parser.test.ts`
- Modify: `backend/src/scripts/tippspiel/parser.ts`

- [ ] **Step 1: Add failing test using real workbook bytes**

Append to `backend/test/unit/tippspiel/parser.test.ts`:

```ts
import { parseWorkbook } from '../../../src/scripts/tippspiel/parser.js'
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
```

- [ ] **Step 2: Run, confirm fail (or skip)**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts -t parseWorkbook`
Expected: FAIL — function does not exist. If `~/Downloads/Tippspiel.xlsx` is absent the test is skipped, so add a fallback below.

- [ ] **Step 3: Add an in-memory fallback test that always runs**

Append to `backend/test/unit/tippspiel/parser.test.ts` before the `parseWorkbook` describe block above:

```ts
function buildMinimalWorkbook(): XLSX.WorkBook {
  // Build a workbook with one sheet that has just enough cells for parseWorkbook
  // not to throw and to produce empty pick blocks for all 11 players.
  const ws: Record<string, XLSX.CellObject> = {}
  // Race header row 4 — Australia at col 3
  ws[XLSX.utils.encode_cell({ r: 3, c: 2 })] = { v: 'Australia', t: 's' } as XLSX.CellObject
  // Preseason single-category label row 4 cols 35,38,41,44,47,50,53
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
```

- [ ] **Step 4: Implement `parseWorkbook`**

Append to `backend/src/scripts/tippspiel/parser.ts`:

```ts
import type { ParsedSeason, ParsedPlayer } from './types.js'

export function parseWorkbook(wb: XLSX.WorkBook, seasonYear: number): ParsedSeason {
  const sheetName = `Tippspiel ${seasonYear}`
  const ws = wb.Sheets[sheetName]
  if (!ws) throw new Error(`sheet "${sheetName}" not found (have: ${wb.SheetNames.join(', ')})`)

  const players: ParsedPlayer[] = PLAYERS_IN_ORDER.map((name, idx) => {
    const nameRow = PLAYER_FIRST_NAME_ROW + idx * PLAYER_ROW_STRIDE
    return {
      excelName: name,
      racePicks: parsePlayerRaceBlock(ws, {
        qualiRow:  nameRow + PLAYER_QUALI_OFFSET,
        sprintRow: nameRow + PLAYER_SPRINT_OFFSET,
        raceRow:   nameRow + PLAYER_RACE_OFFSET
      }),
      preseasonStandings: parsePlayerStandings(ws, idx),
      preseasonSingle:    parsePlayerPreseasonSingle(ws, idx)
    }
  })
  return { seasonYear, players }
}
```

- [ ] **Step 5: Run all parser tests**

Run: `cd backend && npx vitest run test/unit/tippspiel/parser.test.ts`
Expected: all PASS (the real-xlsx integration test is skipped on machines without the file).

- [ ] **Step 6: Commit**

```bash
git add backend/src/scripts/tippspiel/parser.ts backend/test/unit/tippspiel/parser.test.ts
git commit -m "feat(tippspiel): top-level parseWorkbook"
```

---

## Task 8: Importer — write to DB

**Files:**
- Create: `backend/src/scripts/tippspiel/importer.ts`

No unit tests — the importer is a thin wrapper over already-tested repos. Validation comes from Task 11 (running the script end-to-end). Keep it small.

- [ ] **Step 1: Create the importer module**

Create `backend/src/scripts/tippspiel/importer.ts`:

```ts
import { hashPassword } from '../../auth/password.js'
import * as usersRepo from '../../repo/users.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as preseasonPicksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../repo/preseasonStandings.js'
import { getDb } from '../../db/client.js'
import { user as userTable, league as leagueTable } from '../../db/schema.js'
import { eq, sql } from 'drizzle-orm'
import type { ParsedSeason, ParsedPlayer } from './types.js'
import { mapEventName, EVENTS_TO_SKIP } from './mappings.js'
import { SESSION_TYPE_BY_KIND } from './types.js'

const PASSWORD_PLAIN = 'tippspiel-test'
const LEAGUE_NAME = 'Tippspiel 2026 Validation'
const LEAGUE_JOIN_CODE = 'TIPP-2026'
const ANTON_EXCEL_NAME = 'Anton'

function emailFor(excelName: string): string {
  return `${excelName.toLowerCase()}@tippspiel.test`
}

export type ImportSummary = {
  userIdByExcelName: Map<string, string>
  leagueId: string
  predictionsUpserted: number
  preseasonPicksUpserted: number
  preseasonStandingsUpserted: number
  sessionsRescored: number
  skippedSessions: { reason: string; count: number }[]
}

export async function importParsedSeason(parsed: ParsedSeason): Promise<ImportSummary> {
  const db = getDb()
  const passwordHash = await hashPassword(PASSWORD_PLAIN)

  // 1. Upsert users (find-by-email)
  const userIdByExcelName = new Map<string, string>()
  for (const player of parsed.players) {
    const email = emailFor(player.excelName)
    const existing = await db.select().from(userTable).where(eq(userTable.email, email)).limit(1)
    let id: string
    if (existing.length > 0) {
      id = existing[0]!.id
      // Update displayName in case it drifted
      if (existing[0]!.displayName !== player.excelName) {
        await db.update(userTable).set({ displayName: player.excelName, updatedAt: sql`now()` }).where(eq(userTable.id, id))
      }
    } else {
      const created = await usersRepo.insertUser({ email, passwordHash, displayName: player.excelName })
      id = created.id
    }
    userIdByExcelName.set(player.excelName, id)
  }

  const antonId = userIdByExcelName.get(ANTON_EXCEL_NAME)
  if (!antonId) throw new Error('Anton not found among parsed players — required as league owner')

  // 2. Upsert league (find-by-name)
  const existingLeague = await db.select().from(leagueTable).where(eq(leagueTable.name, LEAGUE_NAME)).limit(1)
  let leagueId: string
  if (existingLeague.length > 0) {
    leagueId = existingLeague[0]!.id
  } else {
    // Anton may already own another league (league_owner_uq). Check and bail with clarity.
    const antonsLeagues = await db.select().from(leagueTable).where(eq(leagueTable.ownerUserId, antonId)).limit(1)
    if (antonsLeagues.length > 0) {
      throw new Error(`cannot create "${LEAGUE_NAME}" — Anton already owns league "${antonsLeagues[0]!.name}". Delete it or use the existing one.`)
    }
    const created = await leaguesRepo.createLeagueWithOwner({ name: LEAGUE_NAME, ownerUserId: antonId, joinCode: LEAGUE_JOIN_CODE })
    leagueId = created.id
  }

  // 3. League membership for everyone (insert ignore)
  for (const [name, uid] of userIdByExcelName.entries()) {
    await db.execute(sql`
      INSERT INTO league_member (league_id, user_id)
      VALUES (${leagueId}::uuid, ${uid}::uuid)
      ON CONFLICT (league_id, user_id) DO NOTHING
    `)
    void name
  }

  // 4. Preseason standings + 5. preseason single picks
  let preseasonStandingsUpserted = 0
  let preseasonPicksUpserted = 0
  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    await preseasonStandingsRepo.replaceConstructorPicks(
      uid, parsed.seasonYear,
      player.preseasonStandings.constructors.map((c) => ({ position: c.position, entityId: c.constructorId }))
    )
    await preseasonStandingsRepo.replaceDriverPicks(
      uid, parsed.seasonYear,
      player.preseasonStandings.drivers.map((d) => ({ position: d.position, entityId: d.driverCode }))
    )
    preseasonStandingsUpserted += 2

    for (const [category, vals] of Object.entries(player.preseasonSingle)) {
      await preseasonPicksRepo.upsertPick(uid, parsed.seasonYear, category as any, {
        driverCode: vals!.driverCode,
        constructorId: vals!.constructorId
      })
      preseasonPicksUpserted += 1
    }
  }

  // 6. Per-race predictions
  // Build event-name → eventId map for the season
  const events = await eventsRepo.listForSeason(parsed.seasonYear)
  const eventIdByName = new Map(events.map((e) => [e.name, e.id]))
  // For each event, fetch its sessions once
  const sessionsByEventId = new Map<number, { type: string; id: number }[]>()
  for (const ev of events) {
    const ss = await sessionsRepo.listForEvent(ev.id)
    sessionsByEventId.set(ev.id, ss.map((s) => ({ type: s.type, id: s.id })))
  }

  let predictionsUpserted = 0
  const skipReasons = new Map<string, number>()
  const bump = (r: string) => skipReasons.set(r, (skipReasons.get(r) ?? 0) + 1)

  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    for (const [excelEventName, picks] of Object.entries(player.racePicks)) {
      if (EVENTS_TO_SKIP.has(excelEventName)) continue
      const dbEventName = mapEventName(excelEventName)
      if (dbEventName === null) continue
      const eventId = eventIdByName.get(dbEventName)
      if (eventId === undefined) { bump(`event-not-in-db:${dbEventName}`); continue }
      const sessions = sessionsByEventId.get(eventId) ?? []
      const event = events.find((e) => e.id === eventId)!

      for (const kind of ['quali','sprintQuali','sprint','race'] as const) {
        const list = picks[kind]
        if (list.length === 0) continue  // player didn't tip
        const sessionType = SESSION_TYPE_BY_KIND[kind]
        // Sprint/sprintQuali only on events with has_sprint
        if ((sessionType === 'sprint' || sessionType === 'sprint_quali') && !event.hasSprint) {
          throw new Error(`event ${dbEventName} has no sprint but Excel has ${kind} picks for player ${player.excelName}`)
        }
        const session = sessions.find((s) => s.type === sessionType)
        if (!session) { bump(`session-not-in-db:${dbEventName}:${sessionType}`); continue }
        await predictionsRepo.upsertPredictionWithPicks(uid, session.id, list)
        predictionsUpserted += 1
      }
    }
  }

  return {
    userIdByExcelName,
    leagueId,
    predictionsUpserted,
    preseasonPicksUpserted,
    preseasonStandingsUpserted,
    sessionsRescored: 0,  // filled by caller
    skippedSessions: [...skipReasons.entries()].map(([reason, count]) => ({ reason, count }))
  }
}
```

- [ ] **Step 2: Make sure it typechecks**

Run: `cd backend && npx tsc --noEmit -p tsconfig.json`
Expected: no errors.

If `mapEventName` is unused due to early `EVENTS_TO_SKIP` check, leave the import; it's used inside the loop.

- [ ] **Step 3: Commit**

```bash
git add backend/src/scripts/tippspiel/importer.ts
git commit -m "feat(tippspiel): importer writes users/league/predictions/preseason"
```

---

## Task 9: Validator — Excel vs. App comparison

**Files:**
- Create: `backend/test/unit/tippspiel/validator.test.ts`
- Create: `backend/src/scripts/tippspiel/validator.ts`

- [ ] **Step 1: Write failing tests**

```ts
import { describe, it, expect } from 'vitest'
import { formatComparisonTable, type ComparisonRow } from '../../../src/scripts/tippspiel/validator.js'

describe('formatComparisonTable', () => {
  it('renders headers + one row per player with X/Y per event', () => {
    const rows: ComparisonRow[] = [
      {
        excelName: 'Jan',
        perEvent: {
          'Australia':       { excel: 13, app: 13, hasApp: true },
          'Australian GP':   { excel: 0, app: 0, hasApp: false } // hasApp=false → "n/a"
        },
        excelTotal: 13,
        appTotal:   13
      }
    ]
    const events = ['Australia', 'Australian GP']
    const out = formatComparisonTable(rows, events)
    expect(out).toMatch(/Jan/)
    expect(out).toMatch(/13\/13/)
    expect(out).toMatch(/n\/a/)
    expect(out).toMatch(/Σ Excel/)
    expect(out).toMatch(/Total mismatches:/)
  })

  it('reports mismatches in the trailing summary line', () => {
    const rows: ComparisonRow[] = [
      {
        excelName: 'Lukas',
        perEvent: { 'China': { excel: 16, app: 12, hasApp: true } },
        excelTotal: 16,
        appTotal: 12
      }
    ]
    const out = formatComparisonTable(rows, ['China'])
    expect(out).toMatch(/Total mismatches: 1/)
  })
})
```

- [ ] **Step 2: Run, confirm fail**

Run: `cd backend && npx vitest run test/unit/tippspiel/validator.test.ts`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement validator**

Create `backend/src/scripts/tippspiel/validator.ts`:

```ts
import { getDb } from '../../db/client.js'
import { score, session, event } from '../../db/schema.js'
import { and, eq, sql, inArray } from 'drizzle-orm'
import type { ParsedSeason } from './types.js'
import { mapEventName, EVENTS_TO_SKIP } from './mappings.js'

export type PerEventCell = { excel: number; app: number; hasApp: boolean }
export type ComparisonRow = {
  excelName: string
  perEvent: Record<string, PerEventCell>
  excelTotal: number
  appTotal: number
}

export async function buildComparison(
  parsed: ParsedSeason,
  userIdByExcelName: Map<string, string>
): Promise<{ rows: ComparisonRow[]; events: string[] }> {
  const db = getDb()
  // All Excel race headers in display order — derive from the first player
  const events = parsed.players.length > 0 ? Object.keys(parsed.players[0]!.racePicks) : []

  // Pre-fetch session.points_total per (user, eventName) for this season
  const userIds = [...userIdByExcelName.values()]
  let rows: { userId: string; eventName: string; pts: number }[] = []
  if (userIds.length > 0) {
    const dbRows = await db
      .select({
        userId: score.userId,
        eventName: event.name,
        pts: sql<number>`COALESCE(SUM(${score.pointsTotal}), 0)::int`
      })
      .from(score)
      .innerJoin(session, eq(session.id, score.sessionId))
      .innerJoin(event, eq(event.id, session.eventId))
      .where(and(
        inArray(score.userId, userIds),
        eq(event.seasonYear, parsed.seasonYear),
        eq(score.kind, 'session')
      ))
      .groupBy(score.userId, event.name)
    rows = dbRows.map((r) => ({ userId: r.userId, eventName: r.eventName, pts: r.pts }))
  }
  const appPointsByUserAndEvent = new Map<string, number>()
  for (const r of rows) appPointsByUserAndEvent.set(`${r.userId}|${r.eventName}`, r.pts)

  const result: ComparisonRow[] = []
  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    const perEvent: Record<string, PerEventCell> = {}
    let excelTotal = 0
    let appTotal = 0
    for (const evName of events) {
      const picks = player.racePicks[evName]!
      const excelPts = picks.excelPoints.quali + picks.excelPoints.sprint + picks.excelPoints.race
      excelTotal += excelPts
      if (EVENTS_TO_SKIP.has(evName)) {
        perEvent[evName] = { excel: excelPts, app: 0, hasApp: false }
        continue
      }
      const dbName = mapEventName(evName)
      const appPts = dbName ? appPointsByUserAndEvent.get(`${uid}|${dbName}`) : undefined
      if (appPts === undefined) {
        perEvent[evName] = { excel: excelPts, app: 0, hasApp: false }
      } else {
        perEvent[evName] = { excel: excelPts, app: appPts, hasApp: true }
        appTotal += appPts
      }
    }
    result.push({ excelName: player.excelName, perEvent, excelTotal, appTotal })
  }
  return { rows: result, events }
}

export function formatComparisonTable(rows: ComparisonRow[], events: string[]): string {
  const nameW = Math.max(8, ...rows.map((r) => r.excelName.length))
  const colW  = 10
  const RED   = '\x1b[31m'
  const RESET = '\x1b[0m'
  const isTty = process.stdout.isTTY === true

  const headerCells = events.map((e) => e.slice(0, colW - 1).padEnd(colW))
  const lines: string[] = []
  lines.push('=== Validation: Excel vs. App ===')
  lines.push(['Player'.padEnd(nameW), ...headerCells, 'Σ Excel'.padEnd(10), 'Σ App'.padEnd(10), 'Δ'].join(' '))

  let mismatchCount = 0
  for (const r of rows) {
    const cells = events.map((e) => {
      const cell = r.perEvent[e]!
      if (!cell.hasApp) return 'n/a'.padEnd(colW)
      const txt = `${cell.excel}/${cell.app}`
      const mismatch = cell.excel !== cell.app
      if (mismatch) mismatchCount++
      const padded = txt.padEnd(colW)
      return mismatch && isTty ? `${RED}${padded}${RESET}` : padded
    })
    const delta = r.appTotal - r.excelTotal
    const deltaStr = delta === 0 ? '0' : `${delta > 0 ? '+' : ''}${delta}`
    lines.push([r.excelName.padEnd(nameW), ...cells, String(r.excelTotal).padEnd(10), String(r.appTotal).padEnd(10), deltaStr].join(' '))
  }
  lines.push(`Total mismatches: ${mismatchCount}`)
  return lines.join('\n')
}
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `cd backend && npx vitest run test/unit/tippspiel/validator.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scripts/tippspiel/validator.ts backend/test/unit/tippspiel/validator.test.ts
git commit -m "feat(tippspiel): validator builds excel-vs-app comparison"
```

---

## Task 10: CLI entry point

**Files:**
- Create: `backend/src/scripts/importTippspiel.ts`

- [ ] **Step 1: Create entry script**

```ts
import * as XLSX from 'xlsx'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import { rescoreSession } from '../scoring/rescorer.js'
import { _resetPoolForTests } from '../db/client.js'
import { parseWorkbook } from './tippspiel/parser.js'
import { importParsedSeason } from './tippspiel/importer.js'
import { buildComparison, formatComparisonTable } from './tippspiel/validator.js'

const DEFAULT_PATH = path.join(os.homedir(), 'Downloads', 'Tippspiel.xlsx')
const SEASON_YEAR  = 2026

async function main(): Promise<number> {
  const arg = process.argv[2]
  const xlsxPath = arg ?? DEFAULT_PATH
  if (!fs.existsSync(xlsxPath)) {
    console.error(`File not found: ${xlsxPath}`)
    return 2
  }
  console.log(`Reading ${xlsxPath}`)
  const wb = XLSX.readFile(xlsxPath)
  const parsed = parseWorkbook(wb, SEASON_YEAR)
  console.log(`Parsed ${parsed.players.length} players for season ${parsed.seasonYear}`)

  const summary = await importParsedSeason(parsed)
  console.log(`Imported: ${summary.predictionsUpserted} predictions, ` +
              `${summary.preseasonPicksUpserted} preseason picks, ` +
              `${summary.preseasonStandingsUpserted} preseason standings sets`)
  if (summary.skippedSessions.length > 0) {
    console.log('Skipped:')
    for (const s of summary.skippedSessions) console.log(`  ${s.reason}: ${s.count}`)
  }

  // Rescore every session in the season that has results
  const events = await import('../repo/events.js').then((m) => m.listForSeason(SEASON_YEAR))
  let rescored = 0
  for (const ev of events) {
    const ss = await sessionsRepo.listForEvent(ev.id)
    for (const s of ss) {
      const results = await resultsRepo.listForSession(s.id)
      if (results.length === 0) continue
      await rescoreSession(s.id)
      rescored += 1
    }
  }
  console.log(`Rescored ${rescored} sessions`)

  const comparison = await buildComparison(parsed, summary.userIdByExcelName)
  console.log('')
  console.log(formatComparisonTable(comparison.rows, comparison.events))

  const mismatches = comparison.rows.reduce((acc, r) => {
    return acc + Object.values(r.perEvent).filter((c) => c.hasApp && c.excel !== c.app).length
  }, 0)
  return mismatches === 0 ? 0 : 1
}

main()
  .then(async (code) => { await _resetPoolForTests(); process.exit(code) })
  .catch(async (e) => { console.error(e); await _resetPoolForTests(); process.exit(1) })
```

- [ ] **Step 2: Type-check**

Run: `cd backend && npx tsc --noEmit -p tsconfig.json`
Expected: no errors.

- [ ] **Step 3: Run the full unit suite to make sure nothing else broke**

Run: `cd backend && npx vitest run test/unit/tippspiel`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/src/scripts/importTippspiel.ts
git commit -m "feat(tippspiel): CLI entry — parse → import → rescore → validate"
```

---

## Task 11: End-to-end smoke run

This step is human-in-the-loop verification — no test asserts, but the run must complete and the comparison table must appear.

- [ ] **Step 1: Verify Postgres is running**

Run: `docker ps --format '{{.Names}}' | grep backend-db-1`
Expected: prints `backend-db-1`. If empty, start it: `cd backend && docker compose up -d`.

- [ ] **Step 2: Run the import**

Run: `cd backend && npm run import:tippspiel`
Expected: console output ends with the validation table. Mismatches may be > 0 (that's the point of the tool — we expect to find scoring-engine bugs or pick-data divergences). Exit code 0 or 1, never crashes.

- [ ] **Step 3: Spot-check in DB**

Run:
```
docker exec backend-db-1 psql -U f1pg -d f1pg -c \
  "SELECT u.display_name, COUNT(p.id) AS preds FROM \"user\" u LEFT JOIN prediction p ON p.user_id = u.id WHERE u.email LIKE '%@tippspiel.test' GROUP BY u.display_name ORDER BY u.display_name;"
```
Expected: 11 rows, each with `preds` > 0 (counts vary based on which sessions are in DB and which races the player skipped).

- [ ] **Step 4: Re-run for idempotency**

Run: `cd backend && npm run import:tippspiel`
Expected: same output, no errors, no duplicate users (verify via the same SQL count above — still 11 users).

- [ ] **Step 5: Spot-check league**

Run:
```
docker exec backend-db-1 psql -U f1pg -d f1pg -c \
  "SELECT name, join_code, (SELECT COUNT(*) FROM league_member WHERE league_id = l.id) AS members FROM league l WHERE name = 'Tippspiel 2026 Validation';"
```
Expected: one row, `members = 11`.

- [ ] **Step 6: Document any unexpected mismatches**

If the validation table shows mismatches, write down (in chat with user, not in repo) the user × event × Δ — those are real findings to investigate next. **Do not** silently "fix" the scoring engine to match the Excel; surface them for the user to decide.

- [ ] **Step 7: No commit — this task is verification only**

---

## Task 12: Final sweep

- [ ] **Step 1: Lint and typecheck**

Run: `cd backend && npx tsc --noEmit -p tsconfig.json`
Expected: no errors.

- [ ] **Step 2: Run all backend tests**

Run: `cd backend && npm test`
Expected: all tests pass; no regressions in other suites.

- [ ] **Step 3: Verify package.json scripts are clean**

Open `backend/package.json`, confirm `"import:tippspiel"` is present and `xlsx` is in `devDependencies`.

- [ ] **Step 4: Commit any cleanup**

If something was needed:
```bash
git add -p
git commit -m "chore(tippspiel): final cleanup"
```

If nothing changed, this task ends without a commit.

---

## Notes

- Excel file is read from `~/Downloads/Tippspiel.xlsx` by default. Override with: `npm run import:tippspiel -- /path/to/Tippspiel.xlsx`.
- The `xlsx` package has historical security CVE notices around URL fetching — we only use `readFile` on a local trusted file, so risk is acceptable. Keep it as a `devDependency`.
- Mismatches in the comparison table are **expected** until the scoring engine + crawler data are fully aligned. The whole point of this tool is to surface them.
- If a future Excel version inserts or removes columns, the hard-coded layout constants will break. That's acceptable — we'd update them in one place (`parser.ts`).
- The `xlsx` package is licensed Apache-2.0 (compatible).
