import { and, eq } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { leagueMember, user, league } from '../db/schema.js'

export type LeagueMemberView = {
  userId: string
  displayName: string
  joinedAt: Date
}

export async function add(leagueId: string, userId: string): Promise<void> {
  const db = getDb()
  await db.insert(leagueMember).values({ leagueId, userId })
}

export async function remove(leagueId: string, userId: string): Promise<void> {
  const db = getDb()
  await db.delete(leagueMember).where(
    and(eq(leagueMember.leagueId, leagueId), eq(leagueMember.userId, userId))
  )
}

export async function isMember(leagueId: string, userId: string): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ u: leagueMember.userId }).from(leagueMember).where(
    and(eq(leagueMember.leagueId, leagueId), eq(leagueMember.userId, userId))
  ).limit(1)
  return rows.length > 0
}

export async function listByLeague(leagueId: string): Promise<LeagueMemberView[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: leagueMember.userId,
      displayName: user.displayName,
      joinedAt: leagueMember.joinedAt
    })
    .from(leagueMember)
    .innerJoin(user, eq(user.id, leagueMember.userId))
    .where(eq(leagueMember.leagueId, leagueId))
    .orderBy(leagueMember.joinedAt)
  return rows
}

export type AdminMemberRow = {
  userId: string
  displayName: string
  email: string
  role: 'owner' | 'member'
  joinedAt: Date
}

export async function listByLeagueDetailed(leagueId: string): Promise<AdminMemberRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: leagueMember.userId,
      displayName: user.displayName,
      email: user.email,
      joinedAt: leagueMember.joinedAt,
      ownerUserId: league.ownerUserId
    })
    .from(leagueMember)
    .innerJoin(user, eq(user.id, leagueMember.userId))
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(eq(leagueMember.leagueId, leagueId))
    .orderBy(leagueMember.joinedAt)
  return rows.map((r) => ({
    userId: r.userId,
    displayName: r.displayName,
    email: r.email,
    role: r.userId === r.ownerUserId ? 'owner' : 'member',
    joinedAt: r.joinedAt
  }))
}
