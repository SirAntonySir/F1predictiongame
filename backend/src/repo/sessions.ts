import { and, eq, lt, gt, sql, asc } from 'drizzle-orm'
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
      status: s.status
    })
    .onConflictDoUpdate({
      target: [session.eventId, session.type],
      set: {
        scheduledStart: s.scheduledStart,
        scheduledEnd: s.scheduledEnd
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
  // Eligible: status=scheduled AND end + 30 min < now AND not practice.
  // Only sprint_quali keeps the 7-day floor — its Jolpica endpoint never
  // returns data, and the floor stops us retrying it forever. race /
  // qualifying / sprint stay eligible until they're finished so historical
  // past sessions are picked up after a bootstrap or outage.
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'scheduled'),
        sql`${session.type} NOT IN ('fp1','fp2','fp3')`,
        lt(session.scheduledEnd, sql`now() - interval '30 minutes'`),
        sql`(${session.type} <> 'sprint_quali' OR ${session.scheduledEnd} > now() - interval '7 days')`
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

export async function setOpenF1SessionKey(id: number, key: number | null): Promise<void> {
  const db = getDb()
  await db.update(session).set({ openf1SessionKey: key }).where(eq(session.id, id))
}
