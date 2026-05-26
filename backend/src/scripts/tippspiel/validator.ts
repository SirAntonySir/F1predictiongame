import { getDb } from '../../db/client.js'
import { score, session, event } from '../../db/schema.js'
import { and, eq, sql, inArray } from 'drizzle-orm'
import type { ParsedSeason } from './types.js'
import { mapEventName, EVENTS_TO_SKIP } from './mappings.js'

export type PerEventCell = { excel: number; app: number; hasApp: boolean }
export type ComparisonRow = {
  excelName: string
  perEvent: Record<string, PerEventCell>
  excelTotal: number
  appTotal: number
}

export async function buildComparison(
  parsed: ParsedSeason,
  userIdByExcelName: Map<string, string>
): Promise<{ rows: ComparisonRow[]; events: string[] }> {
  const db = getDb()
  // All Excel race headers in display order — derive from the first player
  const events = parsed.players.length > 0 ? Object.keys(parsed.players[0]!.racePicks) : []

  // Pre-fetch session.points_total per (user, eventName) for this season
  const userIds = [...userIdByExcelName.values()]
  let rows: { userId: string; eventName: string; pts: number }[] = []
  if (userIds.length > 0) {
    const dbRows = await db
      .select({
        userId: score.userId,
        eventName: event.name,
        pts: sql<number>`COALESCE(SUM(${score.pointsTotal}), 0)::int`
      })
      .from(score)
      .innerJoin(session, eq(session.id, score.sessionId))
      .innerJoin(event, eq(event.id, session.eventId))
      .where(and(
        inArray(score.userId, userIds),
        eq(event.seasonYear, parsed.seasonYear),
        eq(score.kind, 'session')
      ))
      .groupBy(score.userId, event.name)
    rows = dbRows.map((r) => ({ userId: r.userId, eventName: r.eventName, pts: r.pts }))
  }
  const appPointsByUserAndEvent = new Map<string, number>()
  for (const r of rows) appPointsByUserAndEvent.set(`${r.userId}|${r.eventName}`, r.pts)

  const result: ComparisonRow[] = []
  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    const perEvent: Record<string, PerEventCell> = {}
    let excelTotal = 0
    let appTotal = 0
    for (const evName of events) {
      const picks = player.racePicks[evName]!
      const excelPts = picks.excelPoints.quali + picks.excelPoints.sprint + picks.excelPoints.race
      excelTotal += excelPts
      if (EVENTS_TO_SKIP.has(evName)) {
        perEvent[evName] = { excel: excelPts, app: 0, hasApp: false }
        continue
      }
      const dbName = mapEventName(evName)
      const appPts = dbName ? appPointsByUserAndEvent.get(`${uid}|${dbName}`) : undefined
      if (appPts === undefined) {
        perEvent[evName] = { excel: excelPts, app: 0, hasApp: false }
      } else {
        perEvent[evName] = { excel: excelPts, app: appPts, hasApp: true }
        appTotal += appPts
      }
    }
    result.push({ excelName: player.excelName, perEvent, excelTotal, appTotal })
  }
  return { rows: result, events }
}

export function formatComparisonTable(rows: ComparisonRow[], events: string[]): string {
  const nameW = Math.max(8, ...rows.map((r) => r.excelName.length))
  const colW  = 10
  const RED   = '\x1b[31m'
  const RESET = '\x1b[0m'
  const isTty = process.stdout.isTTY === true

  const headerCells = events.map((e) => e.slice(0, colW - 1).padEnd(colW))
  const lines: string[] = []
  lines.push('=== Validation: Excel vs. App ===')
  lines.push(['Player'.padEnd(nameW), ...headerCells, 'Σ Excel'.padEnd(10), 'Σ App'.padEnd(10), 'Δ'].join(' '))

  let mismatchCount = 0
  for (const r of rows) {
    const cells = events.map((e) => {
      const cell = r.perEvent[e]!
      if (!cell.hasApp) return 'n/a'.padEnd(colW)
      const txt = `${cell.excel}/${cell.app}`
      const mismatch = cell.excel !== cell.app
      if (mismatch) mismatchCount++
      const padded = txt.padEnd(colW)
      return mismatch && isTty ? `${RED}${padded}${RESET}` : padded
    })
    const delta = r.appTotal - r.excelTotal
    const deltaStr = delta === 0 ? '0' : `${delta > 0 ? '+' : ''}${delta}`
    lines.push([r.excelName.padEnd(nameW), ...cells, String(r.excelTotal).padEnd(10), String(r.appTotal).padEnd(10), deltaStr].join(' '))
  }
  lines.push(`Total mismatches: ${mismatchCount}`)
  return lines.join('\n')
}
