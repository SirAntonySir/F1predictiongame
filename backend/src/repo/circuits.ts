import { and, eq } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { circuit, circuitSvg } from '../db/schema.js'

export type CircuitRow = typeof circuit.$inferSelect

export async function upsertCircuit(c: {
  id: string
  name: string
  countryId: string | null
  latitude: number | null
  longitude: number | null
  currentLayoutId: string | null
}): Promise<void> {
  const db = getDb()
  await db.insert(circuit)
    .values({ ...c })
    .onConflictDoUpdate({
      target: circuit.id,
      set: {
        name: c.name,
        countryId: c.countryId,
        latitude: c.latitude,
        longitude: c.longitude,
        currentLayoutId: c.currentLayoutId,
        fetchedAt: new Date()
      }
    })
}

export async function upsertSvg(row: {
  circuitId: string
  layoutId: string
  detail: string
  variant: string
  svg: string
}): Promise<void> {
  const db = getDb()
  await db.insert(circuitSvg)
    .values(row)
    .onConflictDoUpdate({
      target: [circuitSvg.circuitId, circuitSvg.layoutId, circuitSvg.detail, circuitSvg.variant],
      set: { svg: row.svg, fetchedAt: new Date() }
    })
}

export async function listAll(): Promise<CircuitRow[]> {
  const db = getDb()
  return db.select().from(circuit).orderBy(circuit.name) as Promise<CircuitRow[]>
}

export async function getById(id: string): Promise<CircuitRow | null> {
  const db = getDb()
  const rows = await db.select().from(circuit).where(eq(circuit.id, id)).limit(1)
  return rows[0] ?? null
}

export async function getSvg(
  circuitId: string,
  layoutId: string,
  detail: string,
  variant: string
): Promise<string | null> {
  const db = getDb()
  const rows = await db.select({ svg: circuitSvg.svg })
    .from(circuitSvg)
    .where(and(
      eq(circuitSvg.circuitId, circuitId),
      eq(circuitSvg.layoutId, layoutId),
      eq(circuitSvg.detail, detail),
      eq(circuitSvg.variant, variant)
    ))
    .limit(1)
  return rows[0]?.svg ?? null
}
