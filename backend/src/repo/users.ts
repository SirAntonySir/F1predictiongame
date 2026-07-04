import { eq, sql, ilike, or, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { user, league, leagueMember, prediction } from '../db/schema.js'
import type { User, UserWithSecret } from '../domain/types.js'

export type NewUser = {
  email: string
  passwordHash: string
  displayName: string
}

function toUser(row: typeof user.$inferSelect): User {
  return {
    id: row.id,
    email: row.email,
    displayName: row.displayName,
    avatarConfig: row.avatarConfig,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  }
}

export async function insertUser(n: NewUser): Promise<User> {
  const db = getDb()
  const [row] = await db.insert(user).values({
    email: n.email,
    passwordHash: n.passwordHash,
    displayName: n.displayName
  }).returning()
  return toUser(row!)
}

export async function findById(id: string): Promise<User | null> {
  const db = getDb()
  const rows = await db.select().from(user).where(eq(user.id, id)).limit(1)
  return rows[0] ? toUser(rows[0]) : null
}

export async function findByEmailWithSecret(email: string): Promise<UserWithSecret | null> {
  const db = getDb()
  const rows = await db.select().from(user).where(eq(user.email, email)).limit(1)
  const row = rows[0]
  if (!row) return null
  return { ...toUser(row), passwordHash: row.passwordHash }
}

export async function updateDisplayName(id: string, displayName: string): Promise<User> {
  const db = getDb()
  const [row] = await db
    .update(user)
    .set({ displayName, updatedAt: sql`now()` })
    .where(eq(user.id, id))
    .returning()
  if (!row) throw new Error('user not found: ' + id)
  return toUser(row)
}

export async function updateAvatarConfig(id: string, avatarConfig: string): Promise<User> {
  const db = getDb()
  const [row] = await db
    .update(user)
    .set({ avatarConfig, updatedAt: sql`now()` })
    .where(eq(user.id, id))
    .returning()
  if (!row) throw new Error('user not found: ' + id)
  return toUser(row)
}

export async function updateEmail(id: string, email: string): Promise<User> {
  const db = getDb()
  const [row] = await db
    .update(user)
    .set({ email, updatedAt: sql`now()` })
    .where(eq(user.id, id))
    .returning()
  if (!row) throw new Error('user not found: ' + id)
  return toUser(row)
}

export async function updatePasswordHash(id: string, passwordHash: string): Promise<void> {
  const db = getDb()
  await db
    .update(user)
    .set({ passwordHash, updatedAt: sql`now()` })
    .where(eq(user.id, id))
}

export async function deleteById(id: string): Promise<void> {
  const db = getDb()
  await db.delete(user).where(eq(user.id, id))
}

export type AdminUserRow = {
  id: string
  email: string
  displayName: string
  createdAt: Date
  leagueCount: number
}

export async function listAllWithMeta(
  opts: { query?: string; limit: number; offset: number }
): Promise<{ rows: AdminUserRow[]; total: number }> {
  const db = getDb()
  const where = opts.query && opts.query.trim() !== ''
    ? or(ilike(user.email, `%${opts.query}%`), ilike(user.displayName, `%${opts.query}%`))
    : undefined

  const rows = await db
    .select({
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      createdAt: user.createdAt,
      leagueCount: sql<number>`(
        select count(*)::int from ${leagueMember}
        where ${leagueMember.userId} = ${user.id}
      )`
    })
    .from(user)
    .where(where)
    .orderBy(asc(user.createdAt))
    .limit(opts.limit)
    .offset(opts.offset)

  const totalRows = await db.select({ c: sql<number>`count(*)::int` }).from(user).where(where)
  return { rows, total: totalRows[0]?.c ?? 0 }
}

export type AdminUserDetail = {
  id: string
  email: string
  displayName: string
  createdAt: Date
  updatedAt: Date
  leagues: { id: string; name: string; role: 'owner' | 'member' }[]
  predictionCount: number
}

export async function getDetail(id: string): Promise<AdminUserDetail | null> {
  const db = getDb()
  const rows = await db.select().from(user).where(eq(user.id, id)).limit(1)
  const row = rows[0]
  if (!row) return null

  const leagueRows = await db
    .select({
      id: league.id,
      name: league.name,
      ownerUserId: league.ownerUserId
    })
    .from(leagueMember)
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(eq(leagueMember.userId, id))

  const predCount = await db
    .select({ c: sql<number>`count(*)::int` })
    .from(prediction)
    .where(eq(prediction.userId, id))

  return {
    id: row.id,
    email: row.email,
    displayName: row.displayName,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    leagues: leagueRows.map((l) => ({
      id: l.id,
      name: l.name,
      role: l.ownerUserId === id ? 'owner' : 'member'
    })),
    predictionCount: predCount[0]?.c ?? 0
  }
}
