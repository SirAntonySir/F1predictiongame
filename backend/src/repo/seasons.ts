import { eq, desc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { season } from '../db/schema.js'
import type { Season } from '../domain/types.js'

export async function upsertSeason(s: Season): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    if (s.isCurrent) {
      await tx.update(season).set({ isCurrent: false }).where(eq(season.isCurrent, true))
    }
    await tx
      .insert(season)
      .values({ year: s.year, isCurrent: s.isCurrent })
      .onConflictDoUpdate({
        target: season.year,
        set: { isCurrent: s.isCurrent }
      })
  })
}

export async function getCurrent(): Promise<Season | null> {
  const db = getDb()
  const rows = await db.select().from(season).where(eq(season.isCurrent, true)).limit(1)
  return rows[0] ?? null
}

export async function list(): Promise<Season[]> {
  const db = getDb()
  return db.select().from(season).orderBy(desc(season.year))
}
