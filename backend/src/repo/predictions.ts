import { and, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { prediction, predictionPick } from '../db/schema.js'
import type { Prediction } from '../domain/types.js'
import type { PickInput } from './predictionPicks.js'

function toPrediction(row: typeof prediction.$inferSelect): Prediction {
  return {
    id: row.id,
    userId: row.userId,
    sessionId: row.sessionId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  }
}

export async function insertPrediction(userId: string, sessionId: number): Promise<Prediction> {
  const db = getDb()
  const [row] = await db.insert(prediction).values({ userId, sessionId }).returning()
  return toPrediction(row!)
}

export async function getByUserAndSession(userId: string, sessionId: number): Promise<Prediction | null> {
  const db = getDb()
  const rows = await db.select().from(prediction)
    .where(and(eq(prediction.userId, userId), eq(prediction.sessionId, sessionId)))
    .limit(1)
  return rows[0] ? toPrediction(rows[0]) : null
}

export async function deleteByUserAndSession(userId: string, sessionId: number): Promise<void> {
  const db = getDb()
  await db.delete(prediction).where(and(eq(prediction.userId, userId), eq(prediction.sessionId, sessionId)))
}

/**
 * Atomically insert-or-update a prediction and its picks. Returns the prediction id.
 */
export async function upsertPredictionWithPicks(
  userId: string,
  sessionId: number,
  items: PickInput[]
): Promise<string> {
  const db = getDb()
  return db.transaction(async (tx) => {
    const [row] = await tx.insert(prediction)
      .values({ userId, sessionId })
      .onConflictDoUpdate({
        target: [prediction.userId, prediction.sessionId],
        set: { updatedAt: sql`now()` }
      })
      .returning()
    const id = row!.id

    await tx.delete(predictionPick).where(eq(predictionPick.predictionId, id))
    if (items.length > 0) {
      await tx.insert(predictionPick).values(items.map((i) => ({
        predictionId: id,
        position: i.position,
        driverCode: i.driverCode
      })))
    }
    return id
  })
}

export type PredictionWithPicks = {
  userId: string
  predictionId: string
  picks: PickInput[]
}

export async function listForSessionWithPicks(sessionId: number): Promise<PredictionWithPicks[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: prediction.userId,
      predictionId: prediction.id,
      position: predictionPick.position,
      driverCode: predictionPick.driverCode
    })
    .from(prediction)
    .leftJoin(predictionPick, eq(predictionPick.predictionId, prediction.id))
    .where(eq(prediction.sessionId, sessionId))

  const byPrediction = new Map<string, PredictionWithPicks>()
  for (const r of rows) {
    let p = byPrediction.get(r.predictionId)
    if (!p) {
      p = { userId: r.userId, predictionId: r.predictionId, picks: [] }
      byPrediction.set(r.predictionId, p)
    }
    if (r.position !== null && r.driverCode !== null) {
      p.picks.push({ position: r.position, driverCode: r.driverCode })
    }
  }
  for (const p of byPrediction.values()) {
    p.picks.sort((a, b) => a.position - b.position)
  }
  return Array.from(byPrediction.values())
}
