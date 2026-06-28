import type { SessionResultRow } from '../domain/types.js'
import type { StoredSession } from '../repo/sessions.js'
import { sessionNameFor, type OpenF1DriverLookup } from './parsers.js'

type OpenF1Client = {
  getSessions: (year: number) => Promise<unknown | null>
  getDrivers: (sessionKey: number) => Promise<unknown | null>
  getPosition: (sessionKey: number) => Promise<unknown | null>
}

/** Reduce the OpenF1 /position time-series to the latest position per driver,
 *  join with the drivers lookup, and emit SessionResultRow[] sorted by position.
 *  Drivers missing from the lookup are skipped. raceTime/points/q* are null
 *  (live order carries no times or championship points). */
export function parseLivePositions(raw: unknown, drivers: OpenF1DriverLookup[]): Array<SessionResultRow & { teamColour: string | null }> {
  const byNumber = new Map(drivers.map((d) => [d.driverNumber, d]))
  const latest = new Map<number, { position: number; date: string }>()
  for (const r of (raw as any[]) ?? []) {
    const num = Number(r.driver_number)
    const date = String(r.date ?? '')
    const prev = latest.get(num)
    if (!prev || date > prev.date) latest.set(num, { position: Number(r.position), date })
  }
  const out: Array<{ row: SessionResultRow & { teamColour: string | null }; date: string }> = []
  for (const [num, { position, date }] of latest) {
    const drv = byNumber.get(num)
    if (!drv) continue
    out.push({
      date,
      row: {
        sessionId: 0,
        position,
        driverCode: drv.code,
        driverName: `${drv.givenName} ${drv.familyName}`.trim(),
        constructorId: drv.teamName.toLowerCase().replace(/\s+/g, '_'),
        constructorName: drv.teamName,
        raceTime: null, status: null, points: null,
        fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
        q1: null, q2: null, q3: null,
        teamColour: drv.teamColour
      }
    })
  }
  // Sort by reported position, breaking ties by most-recent update first so a
  // driver who has genuinely moved into a slot ranks ahead of one holding a
  // stale position (e.g. a retired car that stopped updating). Then RE-INDEX to
  // a contiguous 1..N: the /position feed can transiently report the SAME
  // position for two drivers (a retirement keeps its last slot while another
  // advances into it), which on a clean order is a no-op but otherwise would
  // violate the session_result (session_id, position) primary key on persist.
  out.sort((a, b) => a.row.position - b.row.position || (a.date > b.date ? -1 : a.date < b.date ? 1 : 0))
  return out.map(({ row }, i) => ({ ...row, position: i + 1 }))
}

const MATCH_WINDOW_MS = 6 * 60 * 60 * 1000 // 6h around scheduledStart

/** Resolve the OpenF1 session_key for a stored session. Uses the persisted key
 *  if present; otherwise matches OpenF1's session list by name + nearest
 *  date_start within ±6h, persists the result via `persist`, and returns it
 *  (or null if no match). */
export async function resolveOpenF1SessionKey(
  session: StoredSession,
  client: Pick<OpenF1Client, 'getSessions'>,
  persist: (id: number, key: number | null) => Promise<void>
): Promise<number | null> {
  if (session.openf1SessionKey != null) return session.openf1SessionKey
  const year = session.scheduledStart.getUTCFullYear()
  const raw = (await client.getSessions(year)) as any[] | null
  if (!raw) return null
  const wantName = sessionNameFor(session.type)
  const target = session.scheduledStart.getTime()
  let best: { key: number; diff: number } | null = null
  for (const s of raw) {
    if (String(s.session_name) !== wantName) continue
    const diff = Math.abs(new Date(String(s.date_start)).getTime() - target)
    if (diff > MATCH_WINDOW_MS) continue
    if (!best || diff < best.diff) best = { key: Number(s.session_key), diff }
  }
  if (!best) return null
  await persist(session.id, best.key)
  return best.key
}
