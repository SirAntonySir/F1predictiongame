import { describe, it, expect } from 'vitest'
import {
  mapEventName2025,
  mapDriverCode2025,
  mapConstructorId2025,
  EVENTS_TO_SKIP_2025
} from '../../../src/scripts/tippspiel/mappings2025.js'

describe('mapEventName2025', () => {
  it('maps the 2025 Excel headers to canonical Jolpica event names', () => {
    expect(mapEventName2025('Australien')).toBe('Australian Grand Prix')
    expect(mapEventName2025('China')).toBe('Chinese Grand Prix')
    expect(mapEventName2025('Saudi')).toBe('Saudi Arabian Grand Prix')
    expect(mapEventName2025('Imola')).toBe('Emilia Romagna Grand Prix')
    expect(mapEventName2025('Spain')).toBe('Spanish Grand Prix')
    expect(mapEventName2025('Canada')).toBe('Canadian Grand Prix')
    expect(mapEventName2025('Great Britain')).toBe('British Grand Prix')
    expect(mapEventName2025('Dutch')).toBe('Dutch Grand Prix')
    expect(mapEventName2025('Baku')).toBe('Azerbaijan Grand Prix')
    expect(mapEventName2025('Mexico')).toBe('Mexico City Grand Prix')
    expect(mapEventName2025('Brasil')).toBe('São Paulo Grand Prix')
    expect(mapEventName2025('Las Vegas')).toBe('Las Vegas Grand Prix')
    expect(mapEventName2025('Abu Dhabi')).toBe('Abu Dhabi Grand Prix')
  })

  it('does NOT skip Bahrain/Saudi (2025 scores them, unlike 2026)', () => {
    expect(EVENTS_TO_SKIP_2025.size).toBe(0)
    expect(mapEventName2025('Bahrain')).toBe('Bahrain Grand Prix')
  })

  it('throws on an unknown event header', () => {
    expect(() => mapEventName2025('Atlantis')).toThrow(/unknown event/i)
  })
})

describe('mapDriverCode2025', () => {
  it('passes through known three-letter codes (case-insensitive)', () => {
    expect(mapDriverCode2025('Nor')).toBe('NOR')
    expect(mapDriverCode2025('VER')).toBe('VER')
    expect(mapDriverCode2025('Tsu')).toBe('TSU')
  })

  it('maps 2025-specific codes the 2026 parser does not know', () => {
    expect(mapDriverCode2025('Doh')).toBe('DOO') // Doohan: sheet "Doh" -> Ergast DOO
    expect(mapDriverCode2025('Tsu')).toBe('TSU')
  })

  it('maps the "Bae" typo to Bearman (BEA) so the FK resolves', () => {
    expect(mapDriverCode2025('Bae')).toBe('BEA')
  })

  it('maps surnames and full names used in the standings columns', () => {
    expect(mapDriverCode2025('Hülkenberg')).toBe('HUL')
    expect(mapDriverCode2025('Russell')).toBe('RUS')
    expect(mapDriverCode2025('Bortoleto')).toBe('BOR')
    expect(mapDriverCode2025('Max Verstappen')).toBe('VER')
    expect(mapDriverCode2025('Lando Norris')).toBe('NOR')
    expect(mapDriverCode2025('Kimi Antonelli')).toBe('ANT')
  })

  it('throws on a truly unknown driver token', () => {
    expect(() => mapDriverCode2025('Zzz')).toThrow(/unknown driver/i)
  })
})

describe('mapConstructorId2025', () => {
  it('maps the spellings seen in the 2025 sheet to Ergast constructor ids', () => {
    expect(mapConstructorId2025('McLaren')).toBe('mclaren')
    expect(mapConstructorId2025('Merc')).toBe('mercedes')
    expect(mapConstructorId2025('Mercedes')).toBe('mercedes')
    expect(mapConstructorId2025('Fer')).toBe('ferrari')
    expect(mapConstructorId2025('Ferrari')).toBe('ferrari')
    expect(mapConstructorId2025('RedBull')).toBe('red_bull')
    expect(mapConstructorId2025('Red Bull')).toBe('red_bull')
    expect(mapConstructorId2025('Wil')).toBe('williams')
    expect(mapConstructorId2025('Williams')).toBe('williams')
    expect(mapConstructorId2025('RB')).toBe('rb')
    expect(mapConstructorId2025('Visa Red Bull')).toBe('rb')
    expect(mapConstructorId2025('Toro Rosso')).toBe('rb')
    expect(mapConstructorId2025('Aston')).toBe('aston_martin')
    expect(mapConstructorId2025('Haas F1 Team')).toBe('haas')
    expect(mapConstructorId2025('Sauber')).toBe('sauber')
    expect(mapConstructorId2025('Alpine')).toBe('alpine')
  })

  it('throws on an unknown constructor', () => {
    expect(() => mapConstructorId2025('Brabham')).toThrow(/unknown constructor/i)
  })
})
