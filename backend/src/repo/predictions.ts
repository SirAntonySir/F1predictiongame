import { and, eq, inArray, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { leagueMember, prediction, predictionPick, score, user } from '../db/schema.js'
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
  items: PickInput[],
  options: { source?: 'app' | 'import'; importedBy?: string | null } = {}
): Promise<string> {
  const db = getDb()
  const source = options.source ?? 'app'
  const importedBy = options.importedBy ?? null
  const importedAt = source === 'import' ? sql`now()` : sql`null`
  return db.transaction(async (tx) => {
    const [row] = await tx.insert(prediction)
      .values({ userId, sessionId, source, importedBy, importedAt: source === 'import' ? new Date() : null })
      .onConflictDoUpdate({
        target: [prediction.userId, prediction.sessionId],
        set: { updatedAt: sql`now()`, source, importedBy, importedAt }
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

export type LeagueMemberPrediction = {
  userId: string
  displayName: string
  picks: { position: number; driverCode: string }[]
  pointsTotal: number | null
}

/// Every league member's prediction + session score for a single session.
/// Members with no prediction yield an empty `picks` list. Members with no
/// computed score yield `pointsTotal: null`.
export async function listLeagueMemberPredictions(
  leagueId: string,
  sessionId: number
): Promise<LeagueMemberPrediction[]> {
  const db = getDb()

  const members = await db
    .select({ userId: leagueMember.userId, displayName: user.displayName })
    .from(leagueMember)
    .innerJoin(user, eq(user.id, leagueMember.userId))
    .where(eq(leagueMember.leagueId, leagueId))

  if (members.length === 0) return []
  const userIds = members.map((m) => m.userId)

  const predRows = await db
    .select({
      userId: prediction.userId,
      position: predictionPick.position,
      driverCode: predictionPick.driverCode
    })
    .from(prediction)
    .leftJoin(predictionPick, eq(predictionPick.predictionId, prediction.id))
    .where(and(
      eq(prediction.sessionId, sessionId),
      inArray(prediction.userId, userIds)
    ))

  const scoreRows = await db
    .select({ userId: score.userId, pointsTotal: score.pointsTotal })
    .from(score)
    .where(and(
      eq(score.sessionId, sessionId),
      eq(score.kind, 'session'),
      inArray(score.userId, userIds)
    ))

  const picksByUser = new Map<string, { position: number; driverCode: string }[]>()
  for (const r of predRows) {
    if (r.position === null || r.driverCode === null) continue
    const list = picksByUser.get(r.userId) ?? []
    list.push({ position: r.position, driverCode: r.driverCode })
    picksByUser.set(r.userId, list)
  }
  for (const list of picksByUser.values()) {
    list.sort((a, b) => a.position - b.position)
  }

  const scoreByUser = new Map(scoreRows.map((s) => [s.userId, s.pointsTotal]))

  return members.map((m) => ({
    userId: m.userId,
    displayName: m.displayName,
    picks: picksByUser.get(m.userId) ?? [],
    pointsTotal: scoreByUser.get(m.userId) ?? null
  }))
}
