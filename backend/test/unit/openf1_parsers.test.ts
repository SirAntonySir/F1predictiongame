import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  parseSessionResult, parseDrivers, formatDuration, sessionNameFor
} from '../../src/openf1/parsers.js'

function fx(name: string): unknown {
  return JSON.parse(readFileSync(resolve('test/fixtures/openf1', name), 'utf8'))
}

describe('formatDuration', () => {
  it('formats >= 60s as M:SS.mmm with three-decimal millis', () => {
    expect(formatDuration(74.772)).toBe('1:14.772')
    expect(formatDuration(64.0)).toBe('1:04.000')
    expect(formatDuration(120.5)).toBe('2:00.500')
  })
  it('formats < 60s as SS.mmm (no leading zero)', () => {
    expect(formatDuration(45.123)).toBe('45.123')
  })
  it('rounds to milliseconds', () => {
    expect(formatDuration(74.7723)).toBe('1:14.772')
  })
})

describe('sessionNameFor', () => {
  it('maps every SessionType to the OpenF1 session_name', () => {
    expect(sessionNameFor('race')).toBe('Race')
    expect(sessionNameFor('qualifying')).toBe('Qualifying')
    expect(sessionNameFor('sprint')).toBe('Sprint')
    expect(sessionNameFor('sprint_quali')).toBe('Sprint Qualifying')
    expect(sessionNameFor('fp1')).toBe('Practice 1')
    expect(sessionNameFor('fp2')).toBe('Practice 2')
    expect(sessionNameFor('fp3')).toBe('Practice 3')
  })
})

describe('parseDrivers', () => {
  it('extracts code, name, team_name, headshot_url, team_colour (case preserved)', () => {
    const out = parseDrivers(fx('drivers-china-sprintquali.json'))
    const nor = out.find((d) => d.code === 'NOR')
    expect(nor).toBeDefined()
    expect(nor!.givenName).toBe('Lando')
    expect(nor!.familyName).toBe('Norris')
    expect(nor!.teamName).toBe('McLaren')
    expect(nor!.headshotUrl).toMatch(/^https?:\/\//)
    expect(nor!.teamColour).toMatch(/^[0-9A-F]{6}$/) // OpenF1 uses uppercase
  })
})

describe('parseSessionResult', () => {
  it('builds SessionResultRow with formatted q1/q2/q3 from duration array', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json'))
    const rows = parseSessionResult(fx('session_result-sprintquali-china.json'), drivers)
    expect(rows.length).toBeGreaterThanOrEqual(15)
    const p1 = rows.find((r) => r.position === 1)
    expect(p1).toBeDefined()
    expect(p1!.driverCode).toMatch(/^[A-Z]{3}$/)
    expect(p1!.q1).toMatch(/^\d+:\d{2}\.\d{3}$|^\d+\.\d{3}$/)
    expect(p1!.raceTime).toBeNull()
    expect(p1!.points).toBeNull()
  })

  it('skips rows whose driver_number does not resolve to a driver in the lookup', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json')).filter((d) => d.code !== 'NOR')
    const rows = parseSessionResult(fx('session_result-sprintquali-china.json'), drivers)
    expect(rows.every((r) => r.driverCode !== 'NOR')).toBe(true)
  })

  it('marks DSQ / DNF / DNS in status', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json'))
    const synthetic = [
      { position: 20, driver_number: drivers[0].driverNumber, duration: [80.5], gap_to_leader: [0],
        dnf: true, dns: false, dsq: false, number_of_laps: 1, meeting_key: 1, session_key: 1 }
    ]
    const rows = parseSessionResult(synthetic, drivers)
    expect(rows[0].status).toBe('DNF')
  })

  it('produces sparse q1/q2/q3 when duration array is shorter than 3', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json'))
    const synthetic = [
      { position: 16, driver_number: drivers[0].driverNumber, duration: [90.0], gap_to_leader: [0],
        dnf: false, dns: false, dsq: false, number_of_laps: 5, meeting_key: 1, session_key: 1 }
    ]
    const rows = parseSessionResult(synthetic, drivers)
    expect(rows[0].q1).toBe('1:30.000')
    expect(rows[0].q2).toBeNull()
    expect(rows[0].q3).toBeNull()
  })
})
