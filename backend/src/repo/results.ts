import { eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { sessionResult } from '../db/schema.js'
import type { SessionResultRow } from '../domain/types.js'

export async function replaceForSession(sessionId: number, rows: SessionResultRow[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(sessionResult).where(eq(sessionResult.sessionId, sessionId))
    if (rows.length === 0) return
    await tx.insert(sessionResult).values(rows.map((r) => ({ ...r, sessionId })))
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
