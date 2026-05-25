import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { league, leagueMember } from '../db/schema.js'
import type { League } from '../domain/types.js'

export type NewLeague = {
  name: string
  ownerUserId: string
  joinCode: string
}

export type LeagueWithRole = League & { role: 'owner' | 'member' }

function toLeague(row: typeof league.$inferSelect): League {
  return {
    id: row.id,
    ownerUserId: row.ownerUserId,
    name: row.name,
    joinCode: row.joinCode,
    createdAt: row.createdAt
  }
}

export async function createLeagueWithOwner(n: NewLeague): Promise<League> {
  const db = getDb()
  return db.transaction(async (tx) => {
    const [row] = await tx.insert(league).values({
      name: n.name,
      ownerUserId: n.ownerUserId,
      joinCode: n.joinCode
    }).returning()
    await tx.insert(leagueMember).values({ leagueId: row!.id, userId: n.ownerUserId })
    return toLeague(row!)
  })
}

export async function findById(id: string): Promise<League | null> {
  const db = getDb()
  const rows = await db.select().from(league).where(eq(league.id, id)).limit(1)
  return rows[0] ? toLeague(rows[0]) : null
}

export async function findByJoinCode(code: string): Promise<League | null> {
  const db = getDb()
  const rows = await db.select().from(league).where(eq(league.joinCode, code)).limit(1)
  return rows[0] ? toLeague(rows[0]) : null
}

export async function updateName(id: string, name: string): Promise<League> {
  const db = getDb()
  const [row] = await db.update(league).set({ name }).where(eq(league.id, id)).returning()
  if (!row) throw new Error('league not found: ' + id)
  return toLeague(row)
}

export async function updateJoinCode(id: string, joinCode: string): Promise<League> {
  const db = getDb()
  const [row] = await db.update(league).set({ joinCode }).where(eq(league.id, id)).returning()
  if (!row) throw new Error('league not found: ' + id)
  return toLeague(row)
}

export async function deleteById(id: string): Promise<void> {
  const db = getDb()
  await db.delete(league).where(eq(league.id, id))
}

export async function listForUser(userId: string): Promise<LeagueWithRole[]> {
  const db = getDb()
  const rows = await db
    .select({
      id: league.id,
      ownerUserId: league.ownerUserId,
      name: league.name,
      joinCode: league.joinCode,
      createdAt: league.createdAt,
      role: sql<'owner' | 'member'>`CASE WHEN ${league.ownerUserId} = ${userId} THEN 'owner' ELSE 'member' END`
    })
    .from(league)
    .innerJoin(leagueMember, eq(leagueMember.leagueId, league.id))
    .where(eq(leagueMember.userId, userId))
  return rows.map((r) => ({
    id: r.id,
    ownerUserId: r.ownerUserId,
    name: r.name,
    joinCode: r.joinCode,
    createdAt: r.createdAt,
    role: r.role
  }))
}

export async function countMembers(leagueId: string): Promise<number> {
  const db = getDb()
  const rows = await db.select({ c: sql<number>`count(*)::int` }).from(leagueMember).where(eq(leagueMember.leagueId, leagueId))
  return rows[0]?.c ?? 0
}
