import { eq, inArray } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { sessionBestLap } from '../db/schema.js'
import type { BestLap } from '../openf1/parsers.js'

export type BestLapRow = {
  sessionId: number
  driverCode: string
  knockout: number
  lapMs: number
  s1Ms: number | null
  s2Ms: number | null
  s3Ms: number | null
  lapNumber: number | null
}

export async function replaceForSession(sessionId: number, laps: BestLap[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(sessionBestLap).where(eq(sessionBestLap.sessionId, sessionId))
    if (laps.length === 0) return
    await tx.insert(sessionBestLap).values(laps.map((l) => ({
      sessionId,
      driverCode: l.driverCode,
      knockout: l.knockout ?? 0,
      lapMs: l.lapMs,
      s1Ms: l.s1Ms,
      s2Ms: l.s2Ms,
      s3Ms: l.s3Ms,
      lapNumber: l.lapNumber
    })))
  })
}

export async function listForSessions(sessionIds: number[]): Promise<BestLapRow[]> {
  if (sessionIds.length === 0) return []
  const db = getDb()
  const rows = await db.select().from(sessionBestLap).where(inArray(sessionBestLap.sessionId, sessionIds))
  return rows as BestLapRow[]
}
