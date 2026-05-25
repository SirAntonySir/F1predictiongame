import { and, eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { preseasonPickStandingsDriver, preseasonPickStandingsConstructor } from '../db/schema.js'

export type StandingsPickInput = { position: number; entityId: string }

export async function replaceDriverPicks(userId: string, seasonYear: number, picks: StandingsPickInput[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(preseasonPickStandingsDriver).where(and(
      eq(preseasonPickStandingsDriver.userId, userId),
      eq(preseasonPickStandingsDriver.seasonYear, seasonYear)
    ))
    if (picks.length === 0) return
    await tx.insert(preseasonPickStandingsDriver).values(picks.map((p) => ({
      userId, seasonYear, position: p.position, driverCode: p.entityId
    })))
  })
}

export async function replaceConstructorPicks(userId: string, seasonYear: number, picks: StandingsPickInput[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(preseasonPickStandingsConstructor).where(and(
      eq(preseasonPickStandingsConstructor.userId, userId),
      eq(preseasonPickStandingsConstructor.seasonYear, seasonYear)
    ))
    if (picks.length === 0) return
    await tx.insert(preseasonPickStandingsConstructor).values(picks.map((p) => ({
      userId, seasonYear, position: p.position, constructorId: p.entityId
    })))
  })
}

export async function listDriverPicks(userId: string, seasonYear: number): Promise<StandingsPickInput[]> {
  const db = getDb()
  const rows = await db.select({
    position: preseasonPickStandingsDriver.position,
    entityId: preseasonPickStandingsDriver.driverCode
  })
    .from(preseasonPickStandingsDriver)
    .where(and(eq(preseasonPickStandingsDriver.userId, userId), eq(preseasonPickStandingsDriver.seasonYear, seasonYear)))
    .orderBy(asc(preseasonPickStandingsDriver.position))
  return rows
}

export async function listConstructorPicks(userId: string, seasonYear: number): Promise<StandingsPickInput[]> {
  const db = getDb()
  const rows = await db.select({
    position: preseasonPickStandingsConstructor.position,
    entityId: preseasonPickStandingsConstructor.constructorId
  })
    .from(preseasonPickStandingsConstructor)
    .where(and(eq(preseasonPickStandingsConstructor.userId, userId), eq(preseasonPickStandingsConstructor.seasonYear, seasonYear)))
    .orderBy(asc(preseasonPickStandingsConstructor.position))
  return rows
}
