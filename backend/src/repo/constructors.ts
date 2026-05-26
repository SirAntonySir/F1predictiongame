import { eq, isNull, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { constructor } from '../db/schema.js'
import type { Constructor } from '../domain/types.js'

export async function upsertConstructor(c: Constructor): Promise<void> {
  const db = getDb()
  await db
    .insert(constructor)
    .values(c)
    .onConflictDoUpdate({
      target: constructor.id,
      set: {
        name: c.name,
        nationality: c.nationality,
        wikipediaUrl: c.wikipediaUrl,
        imageUrl: c.imageUrl
        // intentionally do NOT touch imageUrlOverride
      }
    })
}

export async function setImageUrl(id: string, url: string | null): Promise<void> {
  const db = getDb()
  await db.update(constructor).set({ imageUrl: url }).where(eq(constructor.id, id))
}

export async function setImageUrlOverride(id: string, url: string | null): Promise<void> {
  const db = getDb()
  await db.update(constructor).set({ imageUrlOverride: url }).where(eq(constructor.id, id))
}

export async function getById(id: string): Promise<Constructor | null> {
  const db = getDb()
  const rows = await db.select().from(constructor).where(eq(constructor.id, id)).limit(1)
  return (rows[0] as Constructor) ?? null
}

export async function listMissingImage(): Promise<Constructor[]> {
  const db = getDb()
  const rows = await db.select().from(constructor).where(isNull(constructor.imageUrl))
  return rows as Constructor[]
}

export async function listAll(): Promise<Constructor[]> {
  const db = getDb()
  const rows = await db.select().from(constructor)
  return rows as Constructor[]
}

export async function exists(id: string): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ c: sql<number>`1` }).from(constructor).where(eq(constructor.id, id)).limit(1)
  return rows.length > 0
}

export async function setTeamColour(id: string, colour: string | null): Promise<void> {
  const db = getDb()
  await db.update(constructor).set({ teamColour: colour }).where(eq(constructor.id, id))
}

export async function listMissingTeamColour(): Promise<Constructor[]> {
  const db = getDb()
  const rows = await db.select().from(constructor).where(isNull(constructor.teamColour))
  return rows as Constructor[]
}
