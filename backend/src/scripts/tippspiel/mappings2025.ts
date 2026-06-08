// Season profile: 2025 name/event/driver/constructor maps.
//
// Kept entirely separate from the 2026 parser (mappings.ts) so the live 2026
// import path is untouched. The 2025 master sheet differs from 2026 in three
// ways this module captures:
//   - event header spellings (Australien/Imola/Spain/Canada/…),
//   - no skipped events (2025 scores Bahrain & Saudi too),
//   - driver tokens include 2025-only codes (TSU, DOO), surnames and a few
//     full names ("Max Verstappen") used in the standings columns.
//
// Targets are the canonical Jolpica/Ergast 2025 ids so the importer's FKs
// (driver.code, constructor.id, event.name) resolve against backfilled data.

export const EVENTS_TO_SKIP_2025: ReadonlySet<string> = new Set()

const EVENT_MAP_2025: Record<string, string> = {
  'Australien':    'Australian Grand Prix',
  'China':         'Chinese Grand Prix',
  'Japan':         'Japanese Grand Prix',
  'Bahrain':       'Bahrain Grand Prix',
  'Saudi':         'Saudi Arabian Grand Prix',
  'Miami':         'Miami Grand Prix',
  'Imola':         'Emilia Romagna Grand Prix',
  'Monaco':        'Monaco Grand Prix',
  'Spain':         'Spanish Grand Prix',
  'Canada':        'Canadian Grand Prix',
  'Austria':       'Austrian Grand Prix',
  'Great Britain': 'British Grand Prix',
  'Belgium':       'Belgian Grand Prix',
  'Hungary':       'Hungarian Grand Prix',
  'Dutch':         'Dutch Grand Prix',
  'Italy':         'Italian Grand Prix',
  'Baku':          'Azerbaijan Grand Prix',
  'Singapore':     'Singapore Grand Prix',
  'USA':           'United States Grand Prix',
  'Mexico':        'Mexico City Grand Prix',
  'Brasil':        'São Paulo Grand Prix',
  'Las Vegas':     'Las Vegas Grand Prix',
  'Qatar':         'Qatar Grand Prix',
  'Abu Dhabi':     'Abu Dhabi Grand Prix'
}

export function mapEventName2025(raw: string): string {
  const trimmed = raw.trim()
  const name = EVENT_MAP_2025[trimmed]
  if (!name) throw new Error(`unknown event: "${raw}"`)
  return name
}

const KNOWN_DRIVER_CODES_2025 = new Set([
  'ALB', 'ALO', 'ANT', 'BEA', 'BOR', 'COL', 'DOO', 'GAS', 'HAD', 'HAM',
  'HUL', 'LAW', 'LEC', 'LIN', 'NOR', 'OCO', 'PIA', 'RUS', 'SAI', 'STR', 'TSU', 'VER'
])

// Aliases: 3-letter sheet variants, surnames, first names, and known typos.
const DRIVER_ALIASES_2025: Record<string, string> = {
  DOH: 'DOO',          // sheet writes "Doh" for Doohan; Ergast code is DOO
  BAE: 'BEA',          // typo for Bearman (only appears at race P5)
  HULK: 'HUL', 'HÜL': 'HUL',
  // surnames (standings columns)
  VERSTAPPEN: 'VER', NORRIS: 'NOR', RUSSELL: 'RUS', PIASTRI: 'PIA', LECLERC: 'LEC',
  HAMILTON: 'HAM', ANTONELLI: 'ANT', HADJAR: 'HAD', BORTOLETO: 'BOR', COLAPINTO: 'COL',
  DOOHAN: 'DOO', TSUNODA: 'TSU', LAWSON: 'LAW', ALBON: 'ALB', SAINZ: 'SAI', GASLY: 'GAS',
  OCON: 'OCO', BEARMAN: 'BEA', STROLL: 'STR', ALONSO: 'ALO', LINDBLAD: 'LIN',
  HULKENBERG: 'HUL', 'HÜLKENBERG': 'HUL',
  // first names occasionally used
  MAX: 'VER', LANDO: 'NOR', OSCAR: 'PIA', CHARLES: 'LEC', KIMI: 'ANT',
  GEORG: 'RUS', GEORGE: 'RUS'
}

function resolveToken(token: string): string | null {
  const up = token.trim().toUpperCase()
  if (DRIVER_ALIASES_2025[up]) return DRIVER_ALIASES_2025[up]
  if (KNOWN_DRIVER_CODES_2025.has(up)) return up
  return null
}

export function mapDriverCode2025(raw: string): string {
  const direct = resolveToken(raw)
  if (direct) return direct
  // Full names like "Max Verstappen" — try the surname (last word), then first.
  const tokens = raw.trim().split(/\s+/)
  if (tokens.length > 1) {
    const last = resolveToken(tokens[tokens.length - 1]!)
    if (last) return last
    const first = resolveToken(tokens[0]!)
    if (first) return first
  }
  throw new Error(`unknown driver code: "${raw}"`)
}

const CONSTRUCTOR_MAP_2025: Record<string, string> = {
  'McLaren': 'mclaren', 'Mclaren': 'mclaren',
  'Merc': 'mercedes', 'Mercedes': 'mercedes',
  'Ferrari': 'ferrari', 'Ferrai': 'ferrari', 'Fer': 'ferrari',
  'RedBull': 'red_bull', 'Red Bull': 'red_bull',
  'Williams': 'williams', 'Wil': 'williams',
  'RB': 'rb', 'Vcarb': 'rb', 'VCarb': 'rb', 'Racing Bulls': 'rb',
  'Visa Red Bull': 'rb', 'Toro Rosso': 'rb',
  'Aston': 'aston_martin', 'Aston Martin': 'aston_martin',
  'Haas': 'haas', 'Haas F1 Team': 'haas',
  'Sauber': 'sauber',
  'Alpine': 'alpine'
}

export function mapConstructorId2025(raw: string): string {
  const id = CONSTRUCTOR_MAP_2025[raw.trim()]
  if (!id) throw new Error(`unknown constructor: "${raw}"`)
  return id
}
