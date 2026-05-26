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
