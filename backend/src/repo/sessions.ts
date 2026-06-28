import { and, eq, gt, sql, asc, desc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { session } from '../db/schema.js'
import type { Session } from '../domain/types.js'

export type StoredSession = Session & { id: number }

export async function upsertSession(s: Session): Promise<StoredSession> {
  const db = getDb()
  const [row] = await db
    .insert(session)
    .values({
      eventId: s.eventId,
      type: s.type,
      scheduledStart: s.scheduledStart,
      scheduledEnd: s.scheduledEnd,
      status: s.status,
      openf1SessionKey: s.openf1SessionKey ?? null
    })
    .onConflictDoUpdate({
      target: [session.eventId, session.type],
      set: {
        scheduledStart: s.scheduledStart,
        scheduledEnd: s.scheduledEnd,
        openf1SessionKey: s.openf1SessionKey ?? null
      }
    })
    .returning()
  return row as StoredSession
}

export async function getById(id: number): Promise<StoredSession | null> {
  const db = getDb()
  const rows = await db.select().from(session).where(eq(session.id, id)).limit(1)
  return (rows[0] as StoredSession) ?? null
}

export async function markFinished(id: number): Promise<void> {
  const db = getDb()
  await db.update(session).set({ status: 'finished' }).where(eq(session.id, id))
}

export async function listCandidates(): Promise<StoredSession[]> {
  const db = getDb()
  // Eligible: status=scheduled AND past scheduled end.
  // Split by source: sessions with an OpenF1 session key are picked up
  // immediately after scheduled end (OpenF1 publishes results within
  // minutes of the chequered flag). Sessions without a key fall back to
  // Jolpica, which lags 30 min–24 h, so we keep the original +30 min gate
  // to avoid hammering Jolpica before the data has any chance of landing.
  // sprint_quali / fp1–fp3 always have an OpenF1 key (Jolpica doesn't
  // publish them), so they take the fast path.
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'scheduled'),
        sql`(
          (${session.openf1SessionKey} IS NOT NULL AND ${session.scheduledEnd} < now())
          OR
          (${session.openf1SessionKey} IS NULL AND ${session.scheduledEnd} < now() - interval '30 minutes')
        )`
      )
    )
  return rows as StoredSession[]
}

export async function nextScheduled(): Promise<StoredSession | null> {
  const db = getDb()
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'scheduled'),
        gt(session.scheduledStart, sql`now()`)
      )
    )
    .orderBy(asc(session.scheduledStart))
    .limit(1)
  return (rows[0] as StoredSession) ?? null
}

export async function listForEvent(eventId: number): Promise<StoredSession[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(session)
    .where(eq(session.eventId, eventId))
    .orderBy(asc(session.scheduledStart))
  return rows as StoredSession[]
}

/// Scheduled sessions whose start falls in (from, to]. The notification
/// dispatcher uses this for both pick reminders (window reaching into the
/// future) and the just-started "session live" broadcast (a short window in the
/// recent past), bounded so the per-minute tick never scans the whole season.
export async function listScheduledStartingBetween(from: Date, to: Date): Promise<StoredSession[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'scheduled'),
        gt(session.scheduledStart, from),
        sql`${session.scheduledStart} <= ${to}`
      )
    )
    .orderBy(asc(session.scheduledStart))
  return rows as StoredSession[]
}

/// Finished sessions whose scheduled end is at/after [cutoff] — the recent set
/// the dispatcher scans for the "results are in" notification.
export async function listFinishedEndedSince(cutoff: Date): Promise<StoredSession[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(session)
    .where(and(eq(session.status, 'finished'), sql`${session.scheduledEnd} >= ${cutoff}`))
    .orderBy(asc(session.scheduledEnd))
  return rows as StoredSession[]
}

export async function setOpenF1SessionKey(id: number, key: number | null): Promise<void> {
  const db = getDb()
  await db.update(session).set({ openf1SessionKey: key }).where(eq(session.id, id))
}

export async function setLastReconciledAt(id: number, at: Date | null): Promise<void> {
  const db = getDb()
  await db.update(session).set({ lastReconciledAt: at }).where(eq(session.id, id))
}

export async function listRecentFinishedWithOpenF1Key(limit: number): Promise<StoredSession[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'finished'),
        sql`${session.openf1SessionKey} IS NOT NULL`
      )
    )
    .orderBy(desc(session.scheduledEnd))
    .limit(limit)
  return rows as StoredSession[]
}
