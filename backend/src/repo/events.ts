import { and, eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { event } from '../db/schema.js'
import type { Event } from '../domain/types.js'

export type StoredEvent = Event & { id: number }

export async function upsertEvent(e: Event): Promise<StoredEvent> {
  const db = getDb()
  const [row] = await db
    .insert(event)
    .values({
      seasonYear: e.seasonYear,
      round: e.round,
      name: e.name,
      circuitName: e.circuitName,
      country: e.country,
      hasSprint: e.hasSprint
    })
    .onConflictDoUpdate({
      target: [event.seasonYear, event.round],
      set: {
        name: e.name,
        circuitName: e.circuitName,
        country: e.country,
        hasSprint: e.hasSprint
      }
    })
    .returning()
  return row as StoredEvent
}

export async function listForSeason(year: number): Promise<StoredEvent[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(event)
    .where(eq(event.seasonYear, year))
    .orderBy(asc(event.round))
  return rows as StoredEvent[]
}

export async function getByRound(year: number, round: number): Promise<StoredEvent | null> {
  const db = getDb()
  const rows = await db
    .select()
    .from(event)
    .where(and(eq(event.seasonYear, year), eq(event.round, round)))
    .limit(1)
  return (rows[0] as StoredEvent) ?? null
}

export async function getById(id: number): Promise<StoredEvent | null> {
  const db = getDb()
  const rows = await db.select().from(event).where(eq(event.id, id)).limit(1)
  return (rows[0] as StoredEvent) ?? null
}
