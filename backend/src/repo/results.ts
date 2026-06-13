import { eq, asc, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { sessionResult } from '../db/schema.js'
import type { SessionResultRow } from '../domain/types.js'

export type ResultSource = 'openf1' | 'jolpica'

export async function replaceForSession(
  sessionId: number,
  rows: SessionResultRow[],
  source: ResultSource = 'jolpica'
): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(sessionResult).where(eq(sessionResult.sessionId, sessionId))
    if (rows.length === 0) return
    await tx.insert(sessionResult).values(rows.map((r) => ({ ...r, sessionId, source })))
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
