import { and, eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { driverStanding, constructorStanding } from '../db/schema.js'
import type { DriverStanding, ConstructorStanding } from '../domain/types.js'

export async function replaceDriverStandings(year: number, rows: DriverStanding[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(driverStanding).where(eq(driverStanding.seasonYear, year))
    if (rows.length === 0) return
    await tx.insert(driverStanding).values(rows)
  })
}

export async function replaceConstructorStandings(year: number, rows: ConstructorStanding[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(constructorStanding).where(eq(constructorStanding.seasonYear, year))
    if (rows.length === 0) return
    await tx.insert(constructorStanding).values(rows)
  })
}

export async function listDriverStandings(year: number): Promise<DriverStanding[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(driverStanding)
    .where(eq(driverStanding.seasonYear, year))
    .orderBy(asc(driverStanding.position))
  return rows as DriverStanding[]
}

export async function listConstructorStandings(year: number): Promise<ConstructorStanding[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(constructorStanding)
    .where(eq(constructorStanding.seasonYear, year))
    .orderBy(asc(constructorStanding.position))
  return rows as ConstructorStanding[]
}

export async function driverHasStandingForYear(driverCode: string, seasonYear: number): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ c: driverStanding.driverCode })
    .from(driverStanding)
    .where(and(eq(driverStanding.driverCode, driverCode), eq(driverStanding.seasonYear, seasonYear)))
    .limit(1)
  return rows.length > 0
}
