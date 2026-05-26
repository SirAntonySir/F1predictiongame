import { describe, it, expect } from 'vitest'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

describe('drivers repo', () => {
  it('upserts and merges Wikipedia image without clobbering manual override', async () => {
    await drivers.upsertDriver({
      code: 'VER', givenName: 'Max', familyName: 'Verstappen',
      nationality: 'Dutch', permanentNumber: 33,
      wikipediaUrl: 'https://en.wikipedia.org/wiki/Max_Verstappen',
      imageUrl: 'https://image.example/auto.png', imageUrlOverride: null, headshotUrl: null
    })
    await drivers.setImageUrlOverride('VER', 'https://image.example/manual.png')
    await drivers.upsertDriver({
      code: 'VER', givenName: 'Max', familyName: 'Verstappen',
      nationality: 'Dutch', permanentNumber: 33,
      wikipediaUrl: 'https://en.wikipedia.org/wiki/Max_Verstappen',
      imageUrl: 'https://image.example/auto2.png', imageUrlOverride: null, headshotUrl: null
    })
    const d = await drivers.getByCode('VER')
    expect(d?.imageUrl).toBe('https://image.example/auto2.png')
    expect(d?.imageUrlOverride).toBe('https://image.example/manual.png')
  })

  it('lists drivers missing an image_url', async () => {
    await drivers.upsertDriver({
      code: 'A', givenName: 'A', familyName: 'A', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
    await drivers.upsertDriver({
      code: 'B', givenName: 'B', familyName: 'B', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: 'https://x', imageUrlOverride: null, headshotUrl: null
    })
    const missing = await drivers.listMissingImage()
    expect(missing.map((d) => d.code)).toEqual(['A'])
  })

  it('exists() reflects presence', async () => {
    expect(await drivers.exists('ZZZ')).toBe(false)
    await drivers.upsertDriver({
      code: 'ZZZ', givenName: 'Z', familyName: 'Z', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
    expect(await drivers.exists('ZZZ')).toBe(true)
  })
})

describe('constructors repo', () => {
  it('upserts and preserves override', async () => {
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull', nationality: 'Austrian',
      wikipediaUrl: null, imageUrl: 'auto', imageUrlOverride: 'manual', teamColour: null
    })
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull Racing', nationality: 'Austrian',
      wikipediaUrl: null, imageUrl: 'auto2', imageUrlOverride: null, teamColour: null
    })
    const c = await constructors.getById('red_bull')
    expect(c?.name).toBe('Red Bull Racing')
    expect(c?.imageUrl).toBe('auto2')
    expect(c?.imageUrlOverride).toBe('manual')
  })
})
