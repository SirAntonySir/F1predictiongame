import type { PreseasonCategory } from '../../domain/types.js'

const DRIVER_ALIAS_OVERRIDES: Record<string, string> = {
  HULK: 'HUL',
  // Full surname aliases used in preseason standings
  VERSTAPPEN:   'VER',
  NORRIS:       'NOR',
  RUSSELL:      'RUS',
  PIASTRI:      'PIA',
  LECLERC:      'LEC',
  HADJAR:       'HAD',
  ANTONELLI:    'ANT',
  HAMILTON:     'HAM',
  GASLY:        'GAS',
  BEARMAN:      'BEA',
  BE:           'BEA',  // abbreviated form found in some cells
  OCON:         'OCO',
  LINDBLAD:     'LIN',
  ALBON:        'ALB',
  BORTOLETO:    'BOR',
  COLAPINTO:    'COL',
  LAWSON:       'LAW',
  HULKENBERG:   'HUL',
  'HÜLKENBERG': 'HUL',
  HÜL:          'HUL',  // abbreviated umlaut form
  SAINZ:        'SAI',
  BOTTAS:       'BOT',
  PEREZ:        'PER',
  ALONSO:       'ALO',
  STROLL:       'STR'
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
  'Mclaren':      'mclaren',
  'Merc':         'mercedes',
  'Mercedes':     'mercedes',
  'Ferrari':      'ferrari',
  'Ferrai':       'ferrari',  // typo in spreadsheet
  'RedBull':      'red_bull',
  'Red Bull':     'red_bull',
  'Alpine':       'alpine',
  'Haas':         'haas',
  'Vcarb':        'rb',
  'VCarb':        'rb',
  'Racing Bulls': 'rb',
  'RB':           'rb',
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
