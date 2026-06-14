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
  /// knockout segment this best lap belongs to. Optional in producers — the
  /// repo defaults it to 0 if omitted.
  knockout?: number
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
      lapMs,
      s1Ms: toMs(l.duration_sector_1),
      s2Ms: toMs(l.duration_sector_2),
      s3Ms: toMs(l.duration_sector_3),
      lapNumber: Number.isFinite(Number(l.lap_number)) ? Number(l.lap_number) : null
    })
  }
  return [...best.values()]
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
