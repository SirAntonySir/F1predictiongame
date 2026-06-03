import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { user } from '../db/schema.js'
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
