import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { subjectiveTruth } from '../db/schema.js'
import type { SubjectiveTruth } from '../domain/types.js'

export type TruthInput = {
  surpriseDriverCode: string | null
  surpriseConstructorId: string | null
  disappointmentDriverCode: string | null
  disappointmentConstructorId: string | null
}

function toTruth(row: typeof subjectiveTruth.$inferSelect): SubjectiveTruth {
  return {
    seasonYear: row.seasonYear,
    surpriseDriverCode: row.surpriseDriverCode,
    surpriseConstructorId: row.surpriseConstructorId,
    disappointmentDriverCode: row.disappointmentDriverCode,
    disappointmentConstructorId: row.disappointmentConstructorId,
    setAt: row.setAt
  }
}

export async function upsertTruth(seasonYear: number, input: TruthInput): Promise<SubjectiveTruth> {
  const db = getDb()
  const [row] = await db.insert(subjectiveTruth)
    .values({ seasonYear, ...input })
    .onConflictDoUpdate({
      target: [subjectiveTruth.seasonYear],
      set: { ...input, setAt: sql`now()` }
    })
    .returning()
  return toTruth(row!)
}

export async function getTruth(seasonYear: number): Promise<SubjectiveTruth | null> {
  const db = getDb()
  const rows = await db.select().from(subjectiveTruth).where(eq(subjectiveTruth.seasonYear, seasonYear)).limit(1)
  return rows[0] ? toTruth(rows[0]) : null
}
