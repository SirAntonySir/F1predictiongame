import { eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { predictionPick } from '../db/schema.js'

export type PickInput = { position: number; driverCode: string }

export async function replaceForPrediction(predictionId: string, items: PickInput[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(predictionPick).where(eq(predictionPick.predictionId, predictionId))
    if (items.length === 0) return
    await tx.insert(predictionPick).values(items.map((i) => ({
      predictionId,
      position: i.position,
      driverCode: i.driverCode
    })))
  })
}

export async function listForPrediction(predictionId: string): Promise<PickInput[]> {
  const db = getDb()
  const rows = await db.select({
    position: predictionPick.position,
    driverCode: predictionPick.driverCode
  }).from(predictionPick).where(eq(predictionPick.predictionId, predictionId)).orderBy(asc(predictionPick.position))
  return rows
}
