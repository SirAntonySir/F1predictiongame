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
    const duration = (r.duration as number[] | undefined) ?? []
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
