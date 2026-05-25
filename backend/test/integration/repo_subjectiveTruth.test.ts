import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as truth from '../../src/repo/subjectiveTruth.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await constructors.upsertConstructor({ id: 'mercedes', name: 'Mercedes', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'HAM', givenName: 'L', familyName: 'H', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
}

describe('subjectiveTruth repo', () => {
  it('upserts and reads back', async () => {
    await seed()
    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'VER',
      surpriseConstructorId: 'red_bull',
      disappointmentDriverCode: 'HAM',
      disappointmentConstructorId: 'mercedes'
    })
    const got = await truth.getTruth(2026)
    expect(got?.surpriseDriverCode).toBe('VER')
    expect(got?.disappointmentDriverCode).toBe('HAM')
  })

  it('upsert replaces existing row', async () => {
    await seed()
    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'VER', surpriseConstructorId: 'red_bull',
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'HAM', surpriseConstructorId: 'mercedes',
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    const got = await truth.getTruth(2026)
    expect(got?.surpriseDriverCode).toBe('HAM')
  })

  it('returns null for an unknown season', async () => {
    await seed()
    expect(await truth.getTruth(2099)).toBeNull()
  })

  it('accepts all-null fields', async () => {
    await seed()
    await truth.upsertTruth(2026, {
      surpriseDriverCode: null, surpriseConstructorId: null,
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    const got = await truth.getTruth(2026)
    expect(got?.surpriseDriverCode).toBeNull()
  })
})
