import { and, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { preseasonPick } from '../db/schema.js'
import type { PreseasonCategory, PreseasonPick } from '../domain/types.js'

function toPick(row: typeof preseasonPick.$inferSelect): PreseasonPick {
  return {
    userId: row.userId,
    seasonYear: row.seasonYear,
    category: row.category,
    driverCode: row.driverCode,
    constructorId: row.constructorId,
    updatedAt: row.updatedAt
  }
}

export async function upsertPick(
  userId: string,
  seasonYear: number,
  category: PreseasonCategory,
  values: { driverCode: string | null; constructorId: string | null }
): Promise<PreseasonPick> {
  const db = getDb()
  const [row] = await db.insert(preseasonPick)
    .values({ userId, seasonYear, category, driverCode: values.driverCode, constructorId: values.constructorId })
    .onConflictDoUpdate({
      target: [preseasonPick.userId, preseasonPick.seasonYear, preseasonPick.category],
      set: {
        driverCode: values.driverCode,
        constructorId: values.constructorId,
        updatedAt: sql`now()`
      }
    })
    .returning()
  return toPick(row!)
}

export async function getPick(userId: string, seasonYear: number, category: PreseasonCategory): Promise<PreseasonPick | null> {
  const db = getDb()
  const rows = await db.select().from(preseasonPick)
    .where(and(
      eq(preseasonPick.userId, userId),
      eq(preseasonPick.seasonYear, seasonYear),
      eq(preseasonPick.category, category)
    )).limit(1)
  return rows[0] ? toPick(rows[0]) : null
}

export async function listForUser(userId: string, seasonYear: number): Promise<PreseasonPick[]> {
  const db = getDb()
  const rows = await db.select().from(preseasonPick)
    .where(and(eq(preseasonPick.userId, userId), eq(preseasonPick.seasonYear, seasonYear)))
  return rows.map(toPick)
}

export async function listForSeason(seasonYear: number): Promise<PreseasonPick[]> {
  const db = getDb()
  const rows = await db.select().from(preseasonPick).where(eq(preseasonPick.seasonYear, seasonYear))
  return rows.map(toPick)
}

export async function deletePick(userId: string, seasonYear: number, category: PreseasonCategory): Promise<void> {
  const db = getDb()
  await db.delete(preseasonPick).where(and(
    eq(preseasonPick.userId, userId),
    eq(preseasonPick.seasonYear, seasonYear),
    eq(preseasonPick.category, category)
  ))
}
