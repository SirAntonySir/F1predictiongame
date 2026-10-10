import { and, eq, asc, or, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { event, session } from '../db/schema.js'
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

export type SeasonSyncResult = {
  /// The stored row of every scheduled event, keyed by its (new) round.
  byRound: Map<number, StoredEvent>
  /// Off the schedule and never ran — deleted, sessions and picks with it.
  removed: StoredEvent[]
  /// Off the schedule but already ran — kept with its results and scores,
  /// renumbered past the calendar so it can't collide with real rounds.
  parked: StoredEvent[]
}

const PARKED_ROUND_OFFSET = 1000

const norm = (s: string) => s.trim().toLowerCase()

/// Brings the season's events in line with [incoming] (the full schedule),
/// matching each Grand Prix to its existing row by identity — circuit + name,
/// then circuit alone (renamed race), then name alone (renamed circuit) —
/// instead of by round. Rounds shift whenever a race is inserted or cancelled
/// mid-season; keying on round re-labelled a row as the next Grand Prix while
/// its sessions, and the picks on them, stayed behind (2026: Singapore's
/// sprint ended up under "Bahrain Grand Prix in Malaysia").
export async function syncSeasonEvents(seasonYear: number, incoming: Event[]): Promise<SeasonSyncResult> {
  const db = getDb()
  return db.transaction(async (tx) => {
    const existing = (await tx.select().from(event).where(eq(event.seasonYear, seasonYear))) as StoredEvent[]
    const matched = new Map<Event, StoredEvent>()
    const passes: ((a: Event, b: Event) => boolean)[] = [
      (a, b) => norm(a.circuitName) === norm(b.circuitName) && norm(a.name) === norm(b.name),
      (a, b) => norm(a.circuitName) === norm(b.circuitName),
      (a, b) => norm(a.name) === norm(b.name)
    ]
    for (const same of passes) {
      const openRows = existing.filter((r) => ![...matched.values()].includes(r))
      const openEvents = incoming.filter((e) => !matched.has(e))
      for (const ev of openEvents) {
        // Unambiguous pairs only — a double-header at one circuit must not be
        // paired on the circuit pass.
        const rows = openRows.filter((r) => same(ev, r))
        if (rows.length !== 1 || openEvents.filter((o) => same(o, rows[0]!)).length !== 1) continue
        matched.set(ev, rows[0]!)
      }
    }

    // Free every round first: rows trading places would otherwise trip the
    // (season, round) unique index halfway through the renumbering.
    for (const row of existing) {
      await tx.update(event).set({ round: -row.id }).where(eq(event.id, row.id))
    }

    const byRound = new Map<number, StoredEvent>()
    for (const ev of incoming) {
      const fields = { round: ev.round, name: ev.name, circuitName: ev.circuitName, country: ev.country, hasSprint: ev.hasSprint }
      const row = matched.get(ev)
      const [stored] = row
        ? await tx.update(event).set(fields).where(eq(event.id, row.id)).returning()
        : await tx.insert(event).values({ seasonYear, ...fields }).returning()
      byRound.set(ev.round, stored as StoredEvent)
    }

    const removed: StoredEvent[] = []
    const parked: StoredEvent[] = []
    const kept = new Set([...matched.values()].map((r) => r.id))
    for (const row of existing) {
      if (kept.has(row.id)) continue
      const ran = await tx
        .select({ id: session.id })
        .from(session)
        .where(and(
          eq(session.eventId, row.id),
          or(
            eq(session.status, 'finished'),
            sql`EXISTS (SELECT 1 FROM session_result sr WHERE sr.session_id = "session"."id")`
          )
        ))
        .limit(1)
      if (ran.length > 0) {
        const round = row.round >= PARKED_ROUND_OFFSET ? row.round : PARKED_ROUND_OFFSET + row.round
        const [stored] = await tx.update(event).set({ round }).where(eq(event.id, row.id)).returning()
        parked.push(stored as StoredEvent)
      } else {
        await tx.delete(event).where(eq(event.id, row.id))
        removed.push(row)
      }
    }
    return { byRound, removed, parked }
  })
}
