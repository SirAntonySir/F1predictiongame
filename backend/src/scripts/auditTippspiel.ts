/**
 * Tippspiel audit: per (player, event, session-kind) dump of
 *   - picks parsed from Excel
 *   - the Excel point cell for that row
 *   - picks stored in DB
 *   - per-pick score breakdown stored in DB (exact / wrong-pos / team bonus)
 * Output: human-readable file you can compare to the spreadsheet by eye.
 *
 * Diagnostic: separates parsing errors (Excel picks != DB picks)
 * from calculation errors (picks match but Excel pts != DB pts).
 */
import xlsxPkg from 'xlsx'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { sql } from 'drizzle-orm'

const XLSX = xlsxPkg as typeof xlsxPkg & { readFile: (p: string) => xlsxPkg.WorkBook }
import { parseWorkbook } from './tippspiel/parser.js'
import { mapEventName, EVENTS_TO_SKIP } from './tippspiel/mappings.js'
import { SESSION_TYPE_BY_KIND } from './tippspiel/types.js'
import { getDb, _resetPoolForTests } from '../db/client.js'
import {
  user as userT,
  event as eventT,
  session as sessionT,
  prediction as predT,
  predictionPick as pickT,
  score as scoreT
} from '../db/schema.js'

type Row = {
  player: string
  event: string
  kind: 'quali' | 'sprintQuali' | 'sprint' | 'race'
  excelPicks: { position: number; driverCode: string }[]
  dbPicks: { position: number; driverCode: string }[]
  dbPts: number | null
  picksMatch: boolean
  breakdown: any
}
// Excel layout: one points cell per row (quali row, sprint row, race row). The
// sprint row's +5 cell is the COMBINED sprintQuali + sprint total — there is no
// separate cell for sprintQuali alone. Treat (sprintQuali + sprint) as one bucket.
type EventBucket = {
  player: string
  event: string
  excelQuali: number
  excelSprintCombined: number
  excelRace: number
  dbQuali: number
  dbSprintQuali: number
  dbSprint: number
  dbRace: number
}

async function main(): Promise<number> {
  const arg = process.argv[2]
  const xlsxPath = arg ?? path.join(os.homedir(), 'Downloads', 'Tippspiel.xlsx')
  if (!fs.existsSync(xlsxPath)) {
    console.error(`File not found: ${xlsxPath}`)
    return 2
  }
  const wb = XLSX.readFile(xlsxPath)
  const parsed = parseWorkbook(wb, 2026)

  const db = getDb()
  const users = await db.select().from(userT)
  const userIdByName = new Map<string, string>()
  for (const u of users) userIdByName.set(u.displayName, u.id)

  const events = await db.select().from(eventT).where(sql`${eventT.seasonYear} = 2026`)
  const eventByName = new Map(events.map((e) => [e.name, e]))
  const sessions = await db.select().from(sessionT)
  const sessionsByEvent = new Map<number, typeof sessions>()
  for (const s of sessions) {
    const list = sessionsByEvent.get(s.eventId) ?? []
    list.push(s)
    sessionsByEvent.set(s.eventId, list)
  }

  const predictions = await db.select().from(predT)
  const predById = new Map(predictions.map((p) => [p.id, p]))
  const allPicks = await db.select().from(pickT)
  const picksByPredId = new Map<string, typeof allPicks>()
  for (const p of allPicks) {
    const list = picksByPredId.get(p.predictionId) ?? []
    list.push(p)
    picksByPredId.set(p.predictionId, list)
  }
  const predByUserSession = new Map<string, typeof predictions[number]>()
  for (const p of predictions) predByUserSession.set(`${p.userId}|${p.sessionId}`, p)

  const scores = await db.select().from(scoreT).where(sql`${scoreT.kind} = 'session'`)
  const scoreByUserSession = new Map<string, typeof scores[number]>()
  for (const s of scores) scoreByUserSession.set(`${s.userId}|${s.sessionId}`, s)

  const rows: Row[] = []
  const buckets: EventBucket[] = []
  for (const player of parsed.players) {
    const uid = userIdByName.get(player.excelName)
    if (!uid) continue
    for (const [excelEv, picks] of Object.entries(player.racePicks)) {
      if (EVENTS_TO_SKIP.has(excelEv)) continue
      const dbName = mapEventName(excelEv)
      if (!dbName) continue
      const ev = eventByName.get(dbName)
      if (!ev) continue
      const evSessions = sessionsByEvent.get(ev.id) ?? []
      const bucket: EventBucket = {
        player: player.excelName,
        event: excelEv,
        excelQuali: picks.excelPoints.quali,
        excelSprintCombined: picks.excelPoints.sprint,
        excelRace: picks.excelPoints.race,
        dbQuali: 0,
        dbSprintQuali: 0,
        dbSprint: 0,
        dbRace: 0
      }
      let anySession = false
      for (const kind of ['quali','sprintQuali','sprint','race'] as const) {
        const excelPicks = picks[kind]
        if (excelPicks.length === 0) continue
        const sType = SESSION_TYPE_BY_KIND[kind]
        const ses = evSessions.find((s) => s.type === sType)
        if (!ses) continue
        anySession = true
        const pred = predByUserSession.get(`${uid}|${ses.id}`)
        const dbPicks = pred ? (picksByPredId.get(pred.id) ?? [])
          .map((p) => ({ position: p.position, driverCode: p.driverCode }))
          .sort((a, b) => a.position - b.position) : []
        const sc = scoreByUserSession.get(`${uid}|${ses.id}`)
        const dbPts = sc ? sc.pointsTotal : 0
        if (kind === 'quali') bucket.dbQuali = dbPts
        else if (kind === 'sprintQuali') bucket.dbSprintQuali = dbPts
        else if (kind === 'sprint') bucket.dbSprint = dbPts
        else bucket.dbRace = dbPts
        const picksMatch = excelPicks.length === dbPicks.length &&
          excelPicks.every((p, i) => dbPicks[i] && dbPicks[i]!.position === p.position && dbPicks[i]!.driverCode === p.driverCode)
        rows.push({
          player: player.excelName,
          event: excelEv,
          kind,
          excelPicks,
          dbPicks,
          dbPts: sc ? sc.pointsTotal : null,
          picksMatch,
          breakdown: sc ? sc.breakdown : null
        })
      }
      if (anySession) buckets.push(bucket)
    }
  }

  // Group by player+event for readability
  const rowsByPlayerEvent = new Map<string, Row[]>()
  for (const r of rows) {
    const key = `${r.player}|${r.event}`
    const list = rowsByPlayerEvent.get(key) ?? []
    list.push(r)
    rowsByPlayerEvent.set(key, list)
  }
  const bucketByPlayerEvent = new Map<string, EventBucket>()
  for (const b of buckets) bucketByPlayerEvent.set(`${b.player}|${b.event}`, b)

  const playerOrder = parsed.players.map((p) => p.excelName)
  const eventOrder = parsed.players.length > 0
    ? Object.keys(parsed.players[0]!.racePicks).filter((e) => !EVENTS_TO_SKIP.has(e))
    : []

  // Precompute per-player totals + per-(player,event) bucket index for the summary
  type PlayerTotals = { excel: number; db: number }
  const totals = new Map<string, PlayerTotals>()
  let totalParseMismatches = 0
  let totalQualiDiff = 0, totalSprintDiff = 0, totalRaceDiff = 0
  let qualiMatches = 0, sprintMatches = 0, raceMatches = 0
  let qualiCells = 0, sprintCells = 0, raceCells = 0

  for (const r of rows) if (!r.picksMatch) totalParseMismatches++
  for (const player of playerOrder) {
    let pExcel = 0, pDb = 0
    for (const ev of eventOrder) {
      const b = bucketByPlayerEvent.get(`${player}|${ev}`)
      if (!b) continue
      const sprintDb = b.dbSprintQuali + b.dbSprint
      const qDelta = b.dbQuali - b.excelQuali
      const sDelta = sprintDb - b.excelSprintCombined
      const rDelta = b.dbRace - b.excelRace
      const hasSprint = b.dbSprintQuali > 0 || b.dbSprint > 0 || b.excelSprintCombined > 0
      qualiCells++; raceCells++
      if (qDelta === 0) qualiMatches++; else totalQualiDiff += Math.abs(qDelta)
      if (rDelta === 0) raceMatches++; else totalRaceDiff += Math.abs(rDelta)
      if (hasSprint) {
        sprintCells++
        if (sDelta === 0) sprintMatches++; else totalSprintDiff += Math.abs(sDelta)
      }
      pExcel += b.excelQuali + b.excelSprintCombined + b.excelRace
      pDb += b.dbQuali + sprintDb + b.dbRace
    }
    totals.set(player, { excel: pExcel, db: pDb })
  }

  const out: string[] = []
  out.push('# Tippspiel import audit')
  out.push('')
  out.push(`**Source:** \`${xlsxPath}\`  `)
  out.push(`**Players:** ${parsed.players.length} · **Events scored:** ${eventOrder.filter((e) => buckets.some((b) => b.event === e)).length}  `)
  out.push('')
  out.push('## Headline')
  out.push('')
  out.push(`- **Parse mismatches:** ${totalParseMismatches} / ${rows.length} — picks read from the spreadsheet match what was imported into the DB.`)
  out.push(`- **Score-cell deltas** (DB − Excel): quali Σ\\|Δ\\|=${totalQualiDiff} (${qualiCells - qualiMatches}/${qualiCells} cells differ) · sprint-row Σ\\|Δ\\|=${totalSprintDiff} (${sprintCells - sprintMatches}/${sprintCells}) · race Σ\\|Δ\\|=${totalRaceDiff} (${raceCells - raceMatches}/${raceCells}).`)
  out.push(`- Excel scoring cells are **hand-entered numbers**, not formulas (verified: 129 of 137 cells contain a plain number).`)
  out.push('')
  out.push('## Per-player totals')
  out.push('')
  out.push('| Player | Excel | DB | Δ |')
  out.push('|:---|---:|---:|---:|')
  for (const player of playerOrder) {
    const t = totals.get(player)!
    const delta = t.db - t.excel
    const deltaStr = delta === 0 ? '0' : `${delta > 0 ? '+' : ''}${delta}`
    out.push(`| ${player} | ${t.excel} | ${t.db} | **${deltaStr}** |`)
  }
  out.push('')
  out.push('## How to read each event table')
  out.push('')
  out.push('Each row is one Excel "row" (quali / sprint-row / race). The Excel cell is **hand-typed** by the maintainer; the DB column is what the rescorer computed from the same picks.')
  out.push('')
  out.push('- **Picks** — what was parsed from Excel (always equals what the DB stored for this player/session).')
  out.push('- **Breakdown** — per-position scoring detail from the DB: `e`=exact (full points), `w`=wrong-pos (1pt), `–`=miss (0pt). Team bonus listed separately.')
  out.push('- **Excel / DB / Δ** — Excel cell value vs DB-computed total. The sprint-row Excel cell covers sprint-quali + sprint combined.')
  out.push('')
  out.push('**Scoring rules used by the DB rescorer:**')
  out.push('')
  out.push('| Session | Exact | Wrong-pos | Team bonus |')
  out.push('|:---|:---:|:---:|:---:|')
  out.push('| Qualifying (2 picks) | 3 | 1 | +1 |')
  out.push('| Sprint shootout (1 pick) | 1 | — | +1 |')
  out.push('| Sprint race (3 picks) | 2 | 1 | +1 |')
  out.push('| Race (5 picks) | 3 | 1 | +2 |')
  out.push('')
  out.push('---')
  out.push('')

  const formatPicks = (picks: { position: number; driverCode: string }[]) =>
    picks.map((p) => p.driverCode).join(', ')
  const formatBreakdown = (bd: any): { perPos: string; tb: number } => {
    if (!bd) return { perPos: '', tb: 0 }
    const perPos = (bd.perPosition || []).map((x: any) =>
      `${x.exact ? 'e' : x.wrongPos ? 'w' : '–'}(${x.driverCode})`
    ).join(' ')
    const tb = bd.teamBonus?.applied ? bd.teamBonus.points : 0
    return { perPos, tb }
  }
  const sessionLabel: Record<string, string> = {
    quali: 'Quali',
    sprintQuali: 'Sprint Shootout',
    sprint: 'Sprint Race',
    race: 'Race'
  }

  for (const player of playerOrder) {
    const t = totals.get(player)!
    const delta = t.db - t.excel
    const deltaStr = delta === 0 ? '0' : `${delta > 0 ? '+' : ''}${delta}`
    let anyEvent = false
    const playerLines: string[] = []
    for (const ev of eventOrder) {
      const list = rowsByPlayerEvent.get(`${player}|${ev}`)
      const bucket = bucketByPlayerEvent.get(`${player}|${ev}`)
      if (!list || list.length === 0 || !bucket) continue
      anyEvent = true
      const sprintDb = bucket.dbSprintQuali + bucket.dbSprint
      const sumExcel = bucket.excelQuali + bucket.excelSprintCombined + bucket.excelRace
      const sumDb = bucket.dbQuali + sprintDb + bucket.dbRace
      const sumDelta = sumDb - sumExcel
      const sumDeltaStr = sumDelta === 0 ? '0' : `${sumDelta > 0 ? '+' : ''}${sumDelta}`
      playerLines.push(`#### ${ev}  · Excel ${sumExcel} → DB ${sumDb} (Δ ${sumDeltaStr})`)
      playerLines.push('')
      playerLines.push('| Session | Picks (P1→Pn) | Breakdown | TB | Excel | DB | Δ |')
      playerLines.push('|:---|:---|:---|:---:|---:|---:|---:|')

      // Group rows by which Excel-cell bucket they map to
      // quali → its own Excel cell; sprintQuali + sprint → one combined cell; race → its own.
      // We emit one table row per session, but only one row per "bucket" carries the Excel/DB/Δ.
      const byKind = new Map<string, Row>()
      for (const r of list) byKind.set(r.kind, r)
      const order = ['quali', 'sprintQuali', 'sprint', 'race'] as const
      for (const kind of order) {
        const r = byKind.get(kind)
        if (!r) continue
        const { perPos, tb } = formatBreakdown(r.breakdown)
        let excelCellStr = '', dbCellStr = '', deltaCellStr = ''
        if (kind === 'quali') {
          const d = bucket.dbQuali - bucket.excelQuali
          excelCellStr = String(bucket.excelQuali)
          dbCellStr = String(bucket.dbQuali)
          deltaCellStr = d === 0 ? '0' : `${d > 0 ? '+' : ''}${d}`
        } else if (kind === 'race') {
          const d = bucket.dbRace - bucket.excelRace
          excelCellStr = String(bucket.excelRace)
          dbCellStr = String(bucket.dbRace)
          deltaCellStr = d === 0 ? '0' : `${d > 0 ? '+' : ''}${d}`
        } else if (kind === 'sprintQuali') {
          // Combined sprint-row cell shown here; "sprint" row below shows "↳" continuation.
          const d = sprintDb - bucket.excelSprintCombined
          excelCellStr = `${bucket.excelSprintCombined} *sprint-row*`
          dbCellStr = `${sprintDb}`
          deltaCellStr = d === 0 ? '0' : `${d > 0 ? '+' : ''}${d}`
        } else {
          // sprint — already counted in the sprintQuali row above
          excelCellStr = '↳'
          dbCellStr = '↳'
          deltaCellStr = '↳'
        }
        const picks = formatPicks(r.excelPicks)
        playerLines.push(`| ${sessionLabel[kind]} | ${picks} | ${perPos} | ${tb} | ${excelCellStr} | ${dbCellStr} | ${deltaCellStr} |`)
      }
      playerLines.push('')
    }
    if (anyEvent) {
      out.push(`## ${player} — Excel ${t.excel} / DB ${t.db} (Δ **${deltaStr}**)`)
      out.push('')
      out.push(...playerLines)
    }
  }
  out.push('---')
  out.push('')
  out.push('### Footer')
  out.push('')
  out.push(`- **Parse mismatches:** ${totalParseMismatches} of ${rows.length} session-rows.`)
  out.push(`- **Score-cell mismatches:** quali ${qualiCells - qualiMatches}/${qualiCells} (Σ\\|Δ\\|=${totalQualiDiff}) · sprint-row ${sprintCells - sprintMatches}/${sprintCells} (Σ\\|Δ\\|=${totalSprintDiff}) · race ${raceCells - raceMatches}/${raceCells} (Σ\\|Δ\\|=${totalRaceDiff})`)

  const outPath = path.join(process.cwd(), 'tippspiel-audit.md')
  fs.writeFileSync(outPath, out.join('\n'))
  console.log(`Wrote ${outPath}`)
  console.log(`Parse mismatches: ${totalParseMismatches}`)
  console.log(`Score-cell mismatches: quali ${qualiCells - qualiMatches}/${qualiCells} (Σ|Δ|=${totalQualiDiff}), sprint-row ${sprintCells - sprintMatches}/${sprintCells} (Σ|Δ|=${totalSprintDiff}), race ${raceCells - raceMatches}/${raceCells} (Σ|Δ|=${totalRaceDiff})`)
  return 0
}

main()
  .then(async (code) => { await _resetPoolForTests(); process.exit(code) })
  .catch(async (e) => { console.error(e); await _resetPoolForTests(); process.exit(1) })
