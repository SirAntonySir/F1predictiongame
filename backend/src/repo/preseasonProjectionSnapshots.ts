import { and, desc, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { preseasonProjectionSnapshot } from '../db/schema.js'

export type Snapshot = {
  userId: string
  seasonYear: number
  afterSessionId: number
  projectedPoints: number
}

/// Insert or refresh the snapshot for (user, season, afterSessionId).
/// Re-running the same rescore overwrites the row in place.
export async function upsertSnapshot(
  userId: string,
  seasonYear: number,
  afterSessionId: number,
  projectedPoints: number
): Promise<void> {
  const db = getDb()
  await db
    .insert(preseasonProjectionSnapshot)
    .values({ userId, seasonYear, afterSessionId, projectedPoints })
    .onConflictDoUpdate({
      target: [
        preseasonProjectionSnapshot.userId,
        preseasonProjectionSnapshot.seasonYear,
        preseasonProjectionSnapshot.afterSessionId
      ],
      set: { projectedPoints, computedAt: sql`now()` }
    })
}

/// Most-recent first. Limit is small — callers typically just want the last
/// two rows to compute a delta.
export async function listRecentForUser(
  userId: string,
  seasonYear: number,
  limit: number
): Promise<Snapshot[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(preseasonProjectionSnapshot)
    .where(and(
      eq(preseasonProjectionSnapshot.userId, userId),
      eq(preseasonProjectionSnapshot.seasonYear, seasonYear)
    ))
    .orderBy(desc(preseasonProjectionSnapshot.afterSessionId))
    .limit(limit)
  return rows.map((r) => ({
    userId: r.userId,
    seasonYear: r.seasonYear,
    afterSessionId: r.afterSessionId,
    projectedPoints: r.projectedPoints
  }))
}
