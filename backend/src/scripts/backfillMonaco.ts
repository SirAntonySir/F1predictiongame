/**
 * One-off backfill of Monaco qualifying + race picks from Monaco.xlsx.
 *
 * Resolves the Monaco quali + race sessions and each user BY NAME, so it runs
 * against any database — point DATABASE_URL at the target.
 *
 *   DRY_RUN=1 npx tsx src/scripts/backfillMonaco.ts [path]   # preview, no writes
 *   npx tsx src/scripts/backfillMonaco.ts [path]             # apply
 *
 * Default xlsx path is ~/Downloads/Monaco.xlsx.
 *
 * Per-player diff: prints CURRENT picks in the DB vs xlsx picks. With
 * conflictPolicy=xlsx-wins, any disagreement is overwritten. Players whose
 * xlsx row is all dashes are skipped (no write, no delete).
 */
import xlsxPkg from 'xlsx'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { and, eq, ilike, inArray } from 'drizzle-orm'
import { getDb, getPool } from '../db/client.js'
import { user, event, session, driver, season, league, leagueMember, prediction, predictionPick } from '../db/schema.js'
import { upsertPredictionWithPicks } from '../repo/predictions.js'
import { picksRequiredFor } from '../scoring/index.js'

const XLSX = xlsxPkg as typeof xlsxPkg & { readFile: (p: string) => xlsxPkg.WorkBook }

const EVENT_MATCH = '%monaco%'
const LEAGUE_NAME = 'The Box'
const SHEET = 'Sheet1'

// Sheet layout: blocks of 7 rows per player starting at row 1.
//   row 0: name (col A)
//   row 2: Quali  — cols B,C
//   row 3: Sprint — (unused for Monaco)
//   row 4: Race   — cols B..F
const BLOCK_STRIDE = 7
const QUALI_OFFSET = 2
const RACE_OFFSET = 4

type XlsxBlock = {
  name: string
  quali: string[] | 'skip'   // [] = empty/no data, ['LEC','HAM'] etc.
  race:  string[] | 'skip'
}

function readCell(ws: xlsxPkg.WorkSheet, r0: number, c0: number): string | null {
  const ref = XLSX.utils.encode_cell({ r: r0, c: c0 })
  const cell = (ws as Record<string, xlsxPkg.CellObject | undefined>)[ref]
  if (!cell || cell.v === null || cell.v === undefined) return null
  const s = String(cell.v).trim()
  return s.length === 0 ? null : s
}

function readRow(ws: xlsxPkg.WorkSheet, r0: number, cols: number[]): (string | null)[] {
  return cols.map((c) => readCell(ws, r0, c))
}

function parsePicks(cells: (string | null)[]): string[] | 'skip' {
  if (cells.length === 0) return 'skip'
  if (cells.every((c) => c === null || c === '---')) return 'skip'
  // Partial — e.g. some "---" some filled. Treat as a hard error; abort.
  if (cells.some((c) => c === null || c === '---')) {
    throw new Error(`Partial pick row: ${JSON.stringify(cells)}`)
  }
  return cells.map((c) => c!.toUpperCase())
}

function parseWorkbook(xlsxPath: string): XlsxBlock[] {
  const wb = XLSX.readFile(xlsxPath)
  const ws = wb.Sheets[SHEET]
  if (!ws) throw new Error(`Sheet "${SHEET}" not found`)
  const ref = ws['!ref']
  if (!ref) throw new Error('Empty sheet')
  const range = XLSX.utils.decode_range(ref)
  const out: XlsxBlock[] = []
  for (let r = 0; r <= range.e.r; r += BLOCK_STRIDE) {
    const name = readCell(ws, r, 0)
    if (!name) continue
    if (name.toLowerCase() === 'korrekt') continue  // ground truth, not a player
    const quali = parsePicks(readRow(ws, r + QUALI_OFFSET, [1, 2]))
    const race  = parsePicks(readRow(ws, r + RACE_OFFSET, [1, 2, 3, 4, 5]))
    out.push({ name: name.trim(), quali, race })
  }
  return out
}

type Plan = {
  name: string
  userId: string
  quali: { picks: { position: number; driverCode: string }[] } | 'skip'
  race:  { picks: { position: number; driverCode: string }[] } | 'skip'
}

const picksFromList = (codes: string[]) => codes.map((c, i) => ({ position: i + 1, driverCode: c }))

const sameList = (
  a: { position: number; driverCode: string }[],
  b: { position: number; driverCode: string }[]
) => a.length === b.length && a.every((x, i) => x.position === b[i]!.position && x.driverCode === b[i]!.driverCode)

const fmtPicks = (picks: { position: number; driverCode: string }[]) =>
  picks.length === 0 ? '(none)' : picks.map((p) => `${p.position}=${p.driverCode}`).join(' ')

async function fetchExistingPicks(
  db: ReturnType<typeof getDb>,
  userId: string,
  sessionId: number
): Promise<{ position: number; driverCode: string }[]> {
  const rows = await db
    .select({ position: predictionPick.position, driverCode: predictionPick.driverCode })
    .from(prediction)
    .leftJoin(predictionPick, eq(predictionPick.predictionId, prediction.id))
    .where(and(eq(prediction.userId, userId), eq(prediction.sessionId, sessionId)))
  const picks = rows
    .filter((r) => r.position !== null && r.driverCode !== null)
    .map((r) => ({ position: r.position!, driverCode: r.driverCode! }))
  picks.sort((a, b) => a.position - b.position)
  return picks
}

async function main(): Promise<number> {
  const xlsxPath = process.argv[2] ?? path.join(os.homedir(), 'Downloads', 'Monaco.xlsx')
  if (!fs.existsSync(xlsxPath)) {
    console.error(`Not found: ${xlsxPath}`)
    return 2
  }
  const dry = !!process.env.DRY_RUN
  console.log(`Reading ${xlsxPath}${dry ? '  [DRY RUN]' : ''}`)

  const blocks = parseWorkbook(xlsxPath)
  console.log(`Parsed ${blocks.length} player blocks: ${blocks.map((b) => b.name).join(', ')}`)

  const db = getDb()

  const [cur] = await db.select().from(season).where(eq(season.isCurrent, true))
  if (!cur) throw new Error('No current season set')

  const sessRows = await db
    .select({ id: session.id, type: session.type, start: session.scheduledStart, evName: event.name })
    .from(session)
    .innerJoin(event, eq(event.id, session.eventId))
    .where(and(
      inArray(session.type, ['qualifying', 'race']),
      ilike(event.name, EVENT_MATCH),
      eq(event.seasonYear, cur.year)
    ))
  const quali = sessRows.find((s) => s.type === 'qualifying')
  const race  = sessRows.find((s) => s.type === 'race')
  if (!quali) throw new Error('No Monaco qualifying session found')
  if (!race)  throw new Error('No Monaco race session found')
  console.log(`Sessions: quali #${quali.id} race #${race.id} (event ${quali.evName}, season ${cur.year})`)

  const reqQ = picksRequiredFor('qualifying')
  const reqR = picksRequiredFor('race')

  const allCodes = [...new Set(blocks.flatMap((b) => [
    ...(b.quali === 'skip' ? [] : b.quali),
    ...(b.race  === 'skip' ? [] : b.race)
  ]))]
  const drv = await db.select({ code: driver.code }).from(driver).where(inArray(driver.code, allCodes))
  const known = new Set(drv.map((d) => d.code))
  for (const c of allCodes) if (!known.has(c)) throw new Error(`Unknown driver code: ${c}`)

  const plan: Plan[] = []
  for (const b of blocks) {
    const rows = await db
      .select({ id: user.id, displayName: user.displayName })
      .from(user)
      .innerJoin(leagueMember, eq(leagueMember.userId, user.id))
      .innerJoin(league, eq(league.id, leagueMember.leagueId))
      .where(and(ilike(user.displayName, b.name), eq(league.name, LEAGUE_NAME)))
    if (rows.length !== 1) {
      throw new Error(`Expected exactly 1 user "${b.name}" in league "${LEAGUE_NAME}", found ${rows.length} [${rows.map((r) => r.displayName).join(', ')}]`)
    }
    const u = rows[0]!
    if (b.quali !== 'skip' && b.quali.length !== reqQ) throw new Error(`${b.name} quali: ${b.quali.length}/${reqQ}`)
    if (b.race  !== 'skip' && b.race.length  !== reqR) throw new Error(`${b.name} race: ${b.race.length}/${reqR}`)
    plan.push({
      name: u.displayName,
      userId: u.id,
      quali: b.quali === 'skip' ? 'skip' : { picks: picksFromList(b.quali) },
      race:  b.race  === 'skip' ? 'skip' : { picks: picksFromList(b.race) }
    })
  }

  // ---- Compare vs DB ----
  const rowsOut: string[] = []
  let writesQ = 0, writesR = 0, sameQ = 0, sameR = 0, skippedQ = 0, skippedR = 0
  for (const p of plan) {
    const eQ = await fetchExistingPicks(db, p.userId, quali.id)
    const eR = await fetchExistingPicks(db, p.userId, race.id)

    // Quali line
    let qStatus: string
    if (p.quali === 'skip') { qStatus = `skip   db=${fmtPicks(eQ)}`; skippedQ++ }
    else if (sameList(eQ, p.quali.picks)) { qStatus = `same   ${fmtPicks(p.quali.picks)}`; sameQ++ }
    else { qStatus = `WRITE  db=${fmtPicks(eQ)}  →  xlsx=${fmtPicks(p.quali.picks)}`; writesQ++ }

    // Race line
    let rStatus: string
    if (p.race === 'skip') { rStatus = `skip   db=${fmtPicks(eR)}`; skippedR++ }
    else if (sameList(eR, p.race.picks)) { rStatus = `same   ${fmtPicks(p.race.picks)}`; sameR++ }
    else { rStatus = `WRITE  db=${fmtPicks(eR)}  →  xlsx=${fmtPicks(p.race.picks)}`; writesR++ }

    rowsOut.push(`${p.name.padEnd(8)}  Q: ${qStatus}`)
    rowsOut.push(`${' '.padEnd(8)}  R: ${rStatus}`)
  }

  console.log('\nDiff:')
  for (const r of rowsOut) console.log('  ' + r)
  console.log(`\nSummary  quali: ${writesQ} write / ${sameQ} same / ${skippedQ} skip   ·   race: ${writesR} write / ${sameR} same / ${skippedR} skip`)

  if (dry) {
    console.log('\nDry run — re-run without DRY_RUN to apply.')
    return 0
  }

  // ---- Apply ----
  let applied = 0
  for (const p of plan) {
    if (p.quali !== 'skip') {
      await upsertPredictionWithPicks(p.userId, quali.id, p.quali.picks)
      applied++
    }
    if (p.race !== 'skip') {
      await upsertPredictionWithPicks(p.userId, race.id, p.race.picks)
      applied++
    }
    console.log(`  ✓ ${p.name}`)
  }
  console.log(`\nApplied ${applied} prediction upserts across sessions #${quali.id} (quali) + #${race.id} (race).`)
  console.log('Note: rescore is NOT triggered here. If the race has already been scored, run rescoreOne or a tick to refresh points.')
  return 0
}

main()
  .then(async (code) => { await getPool().end(); process.exit(code) })
  .catch(async (e) => {
    console.error('ERROR:', e instanceof Error ? e.message : e)
    try { await getPool().end() } catch { /* noop */ }
    process.exit(1)
  })
