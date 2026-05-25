import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'

describe('seasons repo', () => {
  it('upserts season and flips is_current', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    await seasons.upsertSeason({ year: 2025, isCurrent: true })
    const cur = await seasons.getCurrent()
    expect(cur?.year).toBe(2025)
    const all = await seasons.list()
    expect(all.map((s) => s.year).sort()).toEqual([2024, 2025])
  })
})

describe('events repo', () => {
  it('upserts events idempotently by (season, round)', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    await events.upsertEvent({
      seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
    })
    await events.upsertEvent({
      seasonYear: 2024, round: 1, name: 'Bahrain GP', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
    })
    const list = await events.listForSeason(2024)
    expect(list).toHaveLength(1)
    expect(list[0]!.name).toBe('Bahrain GP')
  })

  it('returns event by round', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    await events.upsertEvent({
      seasonYear: 2024, round: 5, name: 'China', circuitName: 'SIC', country: 'China', hasSprint: true
    })
    const ev = await events.getByRound(2024, 5)
    expect(ev?.name).toBe('China')
  })

  it('returns event by id', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: true })
    const inserted = await events.upsertEvent({
      seasonYear: 2024, round: 7, name: 'Imola', circuitName: 'IMO', country: 'Italy', hasSprint: false
    })
    const fetched = await events.getById(inserted.id)
    expect(fetched?.round).toBe(7)
    expect(fetched?.name).toBe('Imola')
  })
})
