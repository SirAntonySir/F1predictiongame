import { eq, isNull, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { driver } from '../db/schema.js'
import type { Driver } from '../domain/types.js'

export async function upsertDriver(d: Driver): Promise<void> {
  const db = getDb()
  await db
    .insert(driver)
    .values(d)
    .onConflictDoUpdate({
      target: driver.code,
      set: {
        givenName: d.givenName,
        familyName: d.familyName,
        nationality: d.nationality,
        permanentNumber: d.permanentNumber,
        wikipediaUrl: d.wikipediaUrl,
        imageUrl: d.imageUrl
        // intentionally do NOT touch imageUrlOverride
      }
    })
}

export async function setImageUrl(code: string, url: string | null): Promise<void> {
  const db = getDb()
  await db.update(driver).set({ imageUrl: url }).where(eq(driver.code, code))
}

export async function setImageUrlOverride(code: string, url: string | null): Promise<void> {
  const db = getDb()
  await db.update(driver).set({ imageUrlOverride: url }).where(eq(driver.code, code))
}

export async function getByCode(code: string): Promise<Driver | null> {
  const db = getDb()
  const rows = await db.select().from(driver).where(eq(driver.code, code)).limit(1)
  return (rows[0] as Driver) ?? null
}

export async function listMissingImage(): Promise<Driver[]> {
  const db = getDb()
  const rows = await db.select().from(driver).where(isNull(driver.imageUrl))
  return rows as Driver[]
}

export async function listAll(): Promise<Driver[]> {
  const db = getDb()
  const rows = await db.select().from(driver)
  return rows as Driver[]
}

export async function exists(code: string): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ c: sql<number>`1` }).from(driver).where(eq(driver.code, code)).limit(1)
  return rows.length > 0
}

export async function setHeadshotUrl(code: string, url: string | null): Promise<void> {
  const db = getDb()
  await db.update(driver).set({ headshotUrl: url }).where(eq(driver.code, code))
}

export async function listMissingHeadshot(): Promise<Driver[]> {
  const db = getDb()
  const rows = await db.select().from(driver).where(isNull(driver.headshotUrl))
  return rows as Driver[]
}
