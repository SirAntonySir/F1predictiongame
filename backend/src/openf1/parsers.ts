import type { SessionResultRow, SessionType } from '../domain/types.js'

export type OpenF1DriverLookup = {
  driverNumber: number
  code: string
  givenName: string
  familyName: string
  teamName: string
  headshotUrl: string | null
  teamColour: string | null
}

export function formatDuration(seconds: number): string {
  const totalMs = Math.round(seconds * 1000)
  const wholeSeconds = Math.floor(totalMs / 1000)
  const ms = totalMs - wholeSeconds * 1000
  const minutes = Math.floor(wholeSeconds / 60)
  const secs = wholeSeconds - minutes * 60
  const msStr = String(ms).padStart(3, '0')
  if (minutes === 0) return `${secs}.${msStr}`
  const secStr = String(secs).padStart(2, '0')
  return `${minutes}:${secStr}.${msStr}`
}

const SESSION_NAME_BY_TYPE: Record<SessionType, string> = {
  race: 'Race',
  qualifying: 'Qualifying',
  sprint: 'Sprint',
  sprint_quali: 'Sprint Qualifying',
  fp1: 'Practice 1',
  fp2: 'Practice 2',
  fp3: 'Practice 3'
}

export function sessionNameFor(type: SessionType): string {
  return SESSION_NAME_BY_TYPE[type]
}

export function parseDrivers(raw: unknown): OpenF1DriverLookup[] {
  const arr = (raw as any[]) ?? []
  return arr.map((d) => ({
    driverNumber: Number(d.driver_number),
    code: String(d.name_acronym),
    givenName: String(d.first_name ?? ''),
    familyName: String(d.last_name ?? ''),
    teamName: String(d.team_name ?? ''),
    headshotUrl: d.headshot_url ?? null,
    teamColour: d.team_colour ?? null
  }))
}

function statusFrom(r: { dnf?: boolean; dns?: boolean; dsq?: boolean }): string | null {
  if (r.dsq) return 'DSQ'
  if (r.dns) return 'DNS'
  if (r.dnf) return 'DNF'
  return null
}

export type BestLap = {
  driverCode: string
  /// 0 for non-knockout sessions (FP/race/sprint), 1/2/3 for the qualifying
  /// knockout segment this best lap belongs to.
  knockout: number
  lapMs: number
  s1Ms: number | null
  s2Ms: number | null
  s3Ms: number | null
  lapNumber: number | null
}

const toMs = (sec: unknown): number | null => {
  const n = Number(sec)
  if (!Number.isFinite(n) || n <= 0) return null
  return Math.round(n * 1000)
}

/// Pick each driver's best valid flying lap from OpenF1 /laps.
///
///   - Pit-out laps are excluded (sectors are warmed-up, not representative).
///   - Laps without a total `lap_duration` are excluded.
///   - For each driver, the lap with the smallest `lap_duration` wins.
///   - Sector durations attach as-is (may be missing for laps where OpenF1
///     dropped a sector — the lap can still be the "best total" even if one
///     sector is null; downstream consumers handle that).
export function parseBestLapsPerDriver(
  rawLaps: unknown,
  drivers: OpenF1DriverLookup[]
): BestLap[] {
  const byNumber = new Map(drivers.map((d) => [d.driverNumber, d]))
  const arr = (rawLaps as any[]) ?? []
  const best = new Map<string, BestLap>()
  for (const l of arr) {
    if (l.is_pit_out_lap === true) continue
    const lapMs = toMs(l.lap_duration)
    if (lapMs == null) continue
    const drv = byNumber.get(Number(l.driver_number))
    if (!drv) continue
    const existing = best.get(drv.code)
    if (existing && existing.lapMs <= lapMs) continue
    best.set(drv.code, {
      driverCode: drv.code,
      knockout: 0,
      lapMs,
      s1Ms: toMs(l.duration_sector_1),
      s2Ms: toMs(l.duration_sector_2),
      s3Ms: toMs(l.duration_sector_3),
      lapNumber: Number.isFinite(Number(l.lap_number)) ? Number(l.lap_number) : null
    })
  }
  return [...best.values()]
}

/// Inverse of formatDuration: parses "M:SS.mmm" or "SS.mmm" into integer ms.
/// Returns null for malformed input.
function parseFormattedDurationMs(s: string | null | undefined): number | null {
  if (s == null) return null
  const m = /^(?:(\d+):)?(\d{1,2})\.(\d{1,3})$/.exec(s.trim())
  if (!m) return null
  const minutes = m[1] ? Number(m[1]) : 0
  const secs = Number(m[2])
  const ms = Number(m[3]!.padEnd(3, '0').slice(0, 3))
  return minutes * 60_000 + secs * 1_000 + ms
}

/// Identifies each driver's best lap in Q1/Q2/Q3 by matching the persisted
/// session_result.q1/q2/q3 lap-time strings against OpenF1 `/laps` entries
/// (lap_duration in seconds → ms with ±2ms tolerance). Returns one BestLap per
/// (driver, knockout) where a match exists; missing knockouts (e.g. driver
/// eliminated in Q1) yield no row for that segment.
///
/// Why match by lap_duration instead of detecting knockout boundaries: we
/// already store the canonical per-knockout best time in session_result, and
/// it's set by the official timing feed — no need to reconstruct the segment
/// boundaries from race-control events.
export function parseKnockoutBestLapsPerDriver(
  rawLaps: unknown,
  drivers: OpenF1DriverLookup[],
  qualiResults: Array<{ driverCode: string; q1: string | null; q2: string | null; q3: string | null }>
): BestLap[] {
  const TOLERANCE_MS = 2
  const byNumber = new Map(drivers.map((d) => [d.driverNumber, d]))
  const resultsByCode = new Map(qualiResults.map((r) => [r.driverCode, r]))
  const lapsByDriver = new Map<string, Array<{ lapMs: number; s1Ms: number | null; s2Ms: number | null; s3Ms: number | null; lapNumber: number | null }>>()
  for (const l of (rawLaps as any[]) ?? []) {
    if (l.is_pit_out_lap === true) continue
    const lapMs = toMs(l.lap_duration)
    if (lapMs == null) continue
    const drv = byNumber.get(Number(l.driver_number))
    if (!drv) continue
    const arr = lapsByDriver.get(drv.code) ?? []
    arr.push({
      lapMs,
      s1Ms: toMs(l.duration_sector_1),
      s2Ms: toMs(l.duration_sector_2),
      s3Ms: toMs(l.duration_sector_3),
      lapNumber: Number.isFinite(Number(l.lap_number)) ? Number(l.lap_number) : null
    })
    lapsByDriver.set(drv.code, arr)
  }

  const out: BestLap[] = []
  for (const drv of drivers) {
    const result = resultsByCode.get(drv.code)
    if (!result) continue
    const driverLaps = lapsByDriver.get(drv.code) ?? []
    // Knockouts are processed in order so an earlier segment's chosen lap
    // can't be re-bound by a later segment when two q-times are within
    // tolerance of each other (a Q1 best of 1:30.500 and Q2 best of 1:30.501
    // would otherwise share the same physical lap).
    const usedLapIdx = new Set<number>()
    for (const k of [1, 2, 3] as const) {
      const targetText = k === 1 ? result.q1 : k === 2 ? result.q2 : result.q3
      const targetMs = parseFormattedDurationMs(targetText)
      if (targetMs == null) continue
      let bestIdx = -1
      let bestDelta = TOLERANCE_MS + 1
      let bestLapNumber = Number.POSITIVE_INFINITY
      for (let i = 0; i < driverLaps.length; i++) {
        if (usedLapIdx.has(i)) continue
        const lap = driverLaps[i]!
        const delta = Math.abs(lap.lapMs - targetMs)
        if (delta > TOLERANCE_MS) continue
        const lapNum = lap.lapNumber ?? Number.POSITIVE_INFINITY
        // Tiebreaker: when two laps have the same delta, prefer the
        // chronologically-earlier one (smaller lap_number). Keeps re-ingestion
        // deterministic regardless of OpenF1 pagination order.
        if (delta < bestDelta || (delta === bestDelta && lapNum < bestLapNumber)) {
          bestIdx = i
          bestDelta = delta
          bestLapNumber = lapNum
        }
      }
      if (bestIdx < 0) continue
      const best = driverLaps[bestIdx]!
      usedLapIdx.add(bestIdx)
      out.push({
        driverCode: drv.code,
        knockout: k,
        lapMs: best.lapMs,
        s1Ms: best.s1Ms,
        s2Ms: best.s2Ms,
        s3Ms: best.s3Ms,
        lapNumber: best.lapNumber
      })
    }
  }
  return out
}

export function parseSessionResult(
  raw: unknown,
  drivers: OpenF1DriverLookup[]
): SessionResultRow[] {
  const byNumber = new Map(drivers.map((d) => [d.driverNumber, d]))
  const arr = (raw as any[]) ?? []
  const out: SessionResultRow[] = []
  for (const r of arr) {
    const drv = byNumber.get(Number(r.driver_number))
    if (!drv) continue
    // OpenF1 returns `duration` two different ways depending on session type:
    //  - quali / sprint_quali: array `[Q1, Q2, Q3]` (with later entries
    //    null/missing when the driver was knocked out earlier),
    //  - fp1 / fp2 / fp3: a scalar number — the driver's best lap of the
    //    session.
    // Normalise to an array so the q1/q2/q3 mapping below works uniformly.
    // For practice the scalar lands in q1 (which is also where
    // result_display.dart and the predict screen's _referenceTimeFor read
    // FP times from).
    const rawDuration = r.duration
    const duration: number[] = Array.isArray(rawDuration)
      ? (rawDuration as number[])
      : typeof rawDuration === 'number'
        ? [rawDuration]
        : []
    out.push({
      sessionId: 0, // caller fills this in
      position: Number(r.position),
      driverCode: drv.code,
      driverName: `${drv.givenName} ${drv.familyName}`.trim(),
      constructorId: drv.teamName.toLowerCase().replace(/\s+/g, '_'),
      constructorName: drv.teamName,
      raceTime: null,
      status: statusFrom(r),
      points: null,
      fastestLap: null,
      fastestLapTime: null,
      fastestLapSpeed: null,
      q1: duration[0] != null ? formatDuration(duration[0]) : null,
      q2: duration[1] != null ? formatDuration(duration[1]) : null,
      q3: duration[2] != null ? formatDuration(duration[2]) : null
    })
  }
  return out
}
