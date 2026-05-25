import { eq, lt, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { appSession } from '../db/schema.js'
import type { AppSession } from '../domain/types.js'

export type NewSession = {
  userId: string
  tokenHash: Buffer
  expiresAt: Date
  userAgent: string | null
}

function toSession(row: typeof appSession.$inferSelect): AppSession {
  return {
    id: row.id,
    userId: row.userId,
    tokenHash: row.tokenHash,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
    expiresAt: row.expiresAt,
    userAgent: row.userAgent
  }
}

export async function insertSession(n: NewSession): Promise<AppSession> {
  const db = getDb()
  const [row] = await db.insert(appSession).values({
    userId: n.userId,
    tokenHash: n.tokenHash,
    expiresAt: n.expiresAt,
    userAgent: n.userAgent
  }).returning()
  return toSession(row!)
}

export async function findByTokenHash(tokenHash: Buffer): Promise<AppSession | null> {
  const db = getDb()
  const rows = await db.select().from(appSession).where(eq(appSession.tokenHash, tokenHash)).limit(1)
  return rows[0] ? toSession(rows[0]) : null
}

export async function touchSession(id: string, newExpiresAt: Date): Promise<void> {
  const db = getDb()
  await db.update(appSession)
    .set({ lastUsedAt: sql`now()`, expiresAt: newExpiresAt })
    .where(eq(appSession.id, id))
}

export async function deleteById(id: string): Promise<void> {
  const db = getDb()
  await db.delete(appSession).where(eq(appSession.id, id))
}

export async function deleteExpired(): Promise<number> {
  const db = getDb()
  const res = await db.delete(appSession).where(lt(appSession.expiresAt, sql`now()`)).returning({ id: appSession.id })
  return res.length
}
