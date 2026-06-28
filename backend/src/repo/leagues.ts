import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { league, leagueMember, user } from '../db/schema.js'
import type { League, LeagueWithSecret } from '../domain/types.js'

export type NewLeague = {
  name: string
  ownerUserId: string
  joinCode: string
  passwordHash?: string | null
}

export type LeagueWithRole = League & { role: 'owner' | 'member' }

function toLeague(row: typeof league.$inferSelect): League {
  return {
    id: row.id,
    ownerUserId: row.ownerUserId,
    name: row.name,
    joinCode: row.joinCode,
    hasPassword: row.passwordHash !== null,
    createdAt: row.createdAt
  }
}

function toLeagueWithSecret(row: typeof league.$inferSelect): LeagueWithSecret {
  return { ...toLeague(row), passwordHash: row.passwordHash };
}

export async function createLeagueWithOwner(n: NewLeague): Promise<League> {
  const db = getDb()
  return db.transaction(async (tx) => {
    const [row] = await tx.insert(league).values({
      name: n.name,
      ownerUserId: n.ownerUserId,
      joinCode: n.joinCode,
      passwordHash: n.passwordHash ?? null
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

/// Returns the league for the given join code with its bcrypt hash. Used
/// only by the join route so it can verify the supplied password without
/// leaking the hash everywhere else.
export async function findByJoinCodeWithSecret(code: string): Promise<LeagueWithSecret | null> {
  const db = getDb()
  const rows = await db.select().from(league).where(eq(league.joinCode, code)).limit(1)
  return rows[0] ? toLeagueWithSecret(rows[0]) : null
}

export async function updatePasswordHash(id: string, passwordHash: string | null): Promise<void> {
  const db = getDb()
  await db.update(league).set({ passwordHash }).where(eq(league.id, id))
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
      passwordHash: league.passwordHash,
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
    hasPassword: r.passwordHash !== null,
    createdAt: r.createdAt,
    role: r.role
  }))
}

export async function countMembers(leagueId: string): Promise<number> {
  const db = getDb()
  const rows = await db.select({ c: sql<number>`count(*)::int` }).from(leagueMember).where(eq(leagueMember.leagueId, leagueId))
  return rows[0]?.c ?? 0
}

export type AdminLeagueRow = {
  id: string
  name: string
  ownerUserId: string
  ownerDisplayName: string
  memberCount: number
  joinCode: string
  hasPassword: boolean
  createdAt: Date
}

export async function listAllWithMeta(): Promise<AdminLeagueRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      id: league.id,
      name: league.name,
      ownerUserId: league.ownerUserId,
      ownerDisplayName: user.displayName,
      joinCode: league.joinCode,
      passwordHash: league.passwordHash,
      createdAt: league.createdAt,
      memberCount: sql<number>`(
        select count(*)::int from ${leagueMember}
        where ${leagueMember.leagueId} = ${league.id}
      )`
    })
    .from(league)
    .innerJoin(user, eq(user.id, league.ownerUserId))
    .orderBy(league.createdAt)
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    ownerUserId: r.ownerUserId,
    ownerDisplayName: r.ownerDisplayName,
    memberCount: r.memberCount,
    joinCode: r.joinCode,
    hasPassword: r.passwordHash !== null,
    createdAt: r.createdAt
  }))
}
