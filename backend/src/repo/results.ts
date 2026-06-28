import { eq, asc, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { sessionResult } from '../db/schema.js'
import type { SessionResultRow } from '../domain/types.js'

export type ResultSource = 'openf1' | 'jolpica'

/// Enforce the session_result invariant — exactly one row per (session, position)
/// with a valid positive position — before persisting. The OpenF1 feeds report
/// position 0/null for not-yet-classified / DNS / DSQ cars, and several can share
/// it; persisting those verbatim violates the (session_id, position) primary key
/// and aborts the whole tick for that session (the recurring "Key (session_id,
/// position)=(40, 0) already exists" crash). Drop unclassified rows and keep the
/// first row seen for any position. A no-op for a clean 1..N classification, so
/// Jolpica/official results pass through unchanged.
function sanitizeForPersist(rows: SessionResultRow[]): SessionResultRow[] {
  const seen = new Set<number>()
  const out: SessionResultRow[] = []
  for (const r of rows) {
    if (!Number.isFinite(r.position) || r.position <= 0) continue
    if (seen.has(r.position)) continue
    seen.add(r.position)
    out.push(r)
  }
  return out
}

export async function replaceForSession(
  sessionId: number,
  rows: SessionResultRow[],
  source: ResultSource = 'jolpica'
): Promise<void> {
  const db = getDb()
  const clean = sanitizeForPersist(rows)
  await db.transaction(async (tx) => {
    await tx.delete(sessionResult).where(eq(sessionResult.sessionId, sessionId))
    if (clean.length === 0) return
    await tx.insert(sessionResult).values(clean.map((r) => ({ ...r, sessionId, source })))
  })
}

export async function listForSession(sessionId: number): Promise<SessionResultRow[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(sessionResult)
    .where(eq(sessionResult.sessionId, sessionId))
    .orderBy(asc(sessionResult.position))
  return rows as SessionResultRow[]
}

/// Most recent constructor id this driver was classified under in the given
/// season. The OpenF1 ingestion path consults this to avoid creating a
/// duplicate constructor row when team_name strings drift mid-season
/// (e.g. "Kick Sauber" → "Stake F1 Team Kick Sauber"). Returns null when the
/// driver has never been classified in this season.
export async function lastConstructorIdForDriverInSeason(
  driverCode: string,
  seasonYear: number
): Promise<string | null> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT sr.constructor_id AS "constructorId"
    FROM session_result sr
    JOIN session ses ON ses.id = sr.session_id
    JOIN event ev    ON ev.id = ses.event_id
    WHERE sr.driver_code = ${driverCode} AND ev.season_year = ${seasonYear}
    ORDER BY ses.scheduled_start DESC
    LIMIT 1
  `)
  const row = (rows as unknown as { rows: { constructorId: string }[] }).rows[0]
  return row?.constructorId ?? null
}
