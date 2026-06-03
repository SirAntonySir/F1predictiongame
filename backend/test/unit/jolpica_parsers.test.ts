import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  parseSchedule, parseRaceResults, parseQualifyingResults,
  parseSprintResults, parseDriverStandings, parseConstructorStandings,
  extractDriversFromResults, extractConstructorsFromResults
} from '../../src/jolpica/parsers.js'

function fx(name: string): unknown {
  return JSON.parse(readFileSync(resolve('test/fixtures/jolpica', name), 'utf8'))
}

describe('parseSchedule', () => {
  it('extracts events and sessions for a season', () => {
    const out = parseSchedule(fx('schedule-2024.json'))
    expect(out.year).toBe(2024)
    expect(out.events.length).toBeGreaterThan(20)
    const bahrain = out.events.find((e) => e.round === 1)
    expect(bahrain).toBeDefined()
    expect(bahrain!.name).toContain('Bahrain')
    expect(bahrain!.sessions.find((s) => s.type === 'race')).toBeDefined()
    expect(bahrain!.sessions.find((s) => s.type === 'qualifying')).toBeDefined()
  })

  it('marks sprint weekends with hasSprint and includes sprint sessions', () => {
    const out = parseSchedule(fx('schedule-2024.json'))
    const china = out.events.find((e) => e.round === 5)
    expect(china?.hasSprint).toBe(true)
    expect(china?.sessions.find((s) => s.type === 'sprint')).toBeDefined()
  })
})

describe('parseRaceResults', () => {
  it('extracts ordered classifications', () => {
    const rows = parseRaceResults(fx('race-2024-1.json'))
    expect(rows.length).toBeGreaterThan(15)
    expect(rows[0]!.position).toBe(1)
    expect(rows[0]!.points).toBeGreaterThan(0)
    expect(rows[0]!.driverCode.length).toBe(3)
  })

  it('returns empty array when Races is empty', () => {
    const empty = { MRData: { RaceTable: { Races: [] } } }
    expect(parseRaceResults(empty)).toEqual([])
  })

  // `deriveMostFastestLaps` checks `fastestLap === '1'` to identify the
  // race-fastest-lap holder. The Jolpica payload carries `FastestLap.rank`
  // (= '1' for the FL holder) and `FastestLap.lap` (the lap number, e.g. '39'),
  // so the parser must surface `rank`, not `lap`.
  it('stores FastestLap.rank — exactly one row per race carries fastestLap = "1"', () => {
    const rows = parseRaceResults(fx('race-2024-1.json'))
    const flHolders = rows.filter((r) => r.fastestLap === '1')
    expect(flHolders).toHaveLength(1)
    expect(rows.every((r) => r.fastestLap === null || /^[0-9]+$/.test(r.fastestLap))).toBe(true)
  })
})

describe('parseQualifyingResults', () => {
  it('extracts Q1/Q2/Q3 splits', () => {
    const rows = parseQualifyingResults(fx('qualifying-2024-1.json'))
    expect(rows.length).toBeGreaterThan(15)
    expect(rows[0]!.q1).toBeDefined()
  })
})

describe('parseSprintResults', () => {
  it('extracts sprint classifications', () => {
    const rows = parseSprintResults(fx('sprint-2024-5.json'))
    expect(rows.length).toBeGreaterThan(10)
    expect(rows[0]!.position).toBe(1)
  })
})

describe('parseDriverStandings', () => {
  it('extracts ordered standings', () => {
    const rows = parseDriverStandings(fx('driver-standings-2024.json'))
    expect(rows.length).toBeGreaterThan(15)
    expect(rows[0]!.position).toBe(1)
  })
})

describe('parseConstructorStandings', () => {
  it('extracts ordered constructor standings', () => {
    const rows = parseConstructorStandings(fx('constructor-standings-2024.json'))
    expect(rows.length).toBeGreaterThan(5)
    expect(rows[0]!.position).toBe(1)
  })
})

describe('extractDriversFromResults', () => {
  it('returns deduped drivers with Wikipedia URLs', () => {
    const drv = extractDriversFromResults(fx('race-2024-1.json'))
    expect(drv.length).toBeGreaterThan(15)
    const codes = drv.map((d) => d.code)
    expect(new Set(codes).size).toBe(codes.length)
    const ver = drv.find((d) => d.code === 'VER')
    expect(ver?.wikipediaUrl).toContain('wikipedia.org')
  })
})

describe('extractConstructorsFromResults', () => {
  it('returns deduped constructors with Wikipedia URLs', () => {
    const ctors = extractConstructorsFromResults(fx('race-2024-1.json'))
    expect(ctors.length).toBeGreaterThan(5)
    const rb = ctors.find((c) => c.id === 'red_bull')
    expect(rb?.wikipediaUrl).toContain('wikipedia.org')
  })
})

import { JolpicaClient } from '../../src/jolpica/client.js'

describe('JolpicaClient', () => {
  it('returns null on 404', async () => {
    const c = new JolpicaClient('https://x', async () => new Response(null, { status: 404 }))
    expect(await c.getSprintResults(2024, 99)).toBeNull()
  })
  it('returns null on 400 (Jolpica unsupported endpoint)', async () => {
    const c = new JolpicaClient('https://x', async () => new Response('{}', { status: 400 }))
    expect(await c.getSprintQualifyingResults(2024, 5)).toBeNull()
  })
  it('throws on 5xx', async () => {
    const c = new JolpicaClient('https://x', async () => new Response('boom', { status: 500 }))
    await expect(c.getRaceResults(2024, 1)).rejects.toThrow(/500/)
  })
})
