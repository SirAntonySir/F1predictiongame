/**
 * Backfill a full Tippspiel season into the database end-to-end:
 *   1. load reference data (events/sessions/results/standings) from the F1 API,
 *   2. import the league's picks from the Excel sheet,
 *   3. set the after-season subjective truth,
 *   4. rescore every session + the preseason.
 *
 * Targets whatever DATABASE_URL points at, so it runs against dev or prod.
 * Use --dry-run FIRST against prod: it parses the sheet, resolves the
 * name→account mapping against the live accounts, and reports counts WITHOUT
 * writing anything. The real run is idempotent (upserts / replace-for-session),
 * so re-running is safe.
 *
 * Usage:
 *   tsx src/scripts/backfillSeason.ts [year] [path-to-xlsx] [--dry-run]
 *   (defaults: year=2025, path=~/Downloads/Tippspiel-25.xlsx)
 */
import xlsxPkg from 'xlsx'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { eq } from 'drizzle-orm'
import { getDb, _resetPoolForTests } from '../db/client.js'
import { user as userTable, league as leagueTable } from '../db/schema.js'
import * as seasonsRepo from '../repo/seasons.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as truthRepo from '../repo/subjectiveTruth.js'
import { rescoreSession } from '../scoring/rescorer.js'
import { rescorePreseasonForSeason } from '../preseason/rescorer.js'
import { parseWorkbook2025 } from './tippspiel/parser2025.js'
import { importParsedSeason2025, DEFAULT_ALIASES } from './tippspiel/importer2025.js'
import { backfillSeasonData } from './backfillSeasonData.js'
import type { ParsedSeason } from './tippspiel/types.js'

const XLSX = xlsxPkg as typeof xlsxPkg & { readFile: (p: string) => xlsxPkg.WorkBook }

const EXPECTED: Record<string, number> = { quali: 2, sprintQuali: 1, sprint: 3, race: 5 }
// After-season questionnaire answers for 2025 (surprise / disappointment only).
const SUBJECTIVE_TRUTH_2025 = {
  surpriseDriverCode: 'HAD', surpriseConstructorId: 'sauber',
  disappointmentDriverCode: 'HAM', disappointmentConstructorId: 'alpine'
}
const LEAGUE_NAME = 'The Box'

function countPicks(parsed: ParsedSeason) {
  let valid = 0, partial = 0
  for (const p of parsed.players) {
    for (const rp of Object.values(p.racePicks)) {
      for (const kind of ['quali', 'sprintQuali', 'sprint', 'race'] as const) {
        const n = rp[kind].length
        if (n === 0) continue
        if (n === EXPECTED[kind]) valid++; else partial++
      }
    }
  }
  return { valid, partial }
}

async function dryRun(parsed: ParsedSeason, year: number): Promise<void> {
  const db = getDb()
  const users = await db.select().from(userTable)
  const idByName = new Map(users.map((u) => [u.displayName, u.id]))
  const season = (await seasonsRepo.list()).find((s) => s.year === year)
  const box = (await db.select().from(leagueTable).where(eq(leagueTable.name, LEAGUE_NAME)))[0]

  console.log(`\n=== DRY RUN — season ${year} — NO WRITES ===\n`)
  console.log(`Sheet: ${parsed.players.length} players`)
  console.log(`Season ${year} in DB: ${season ? `yes (is_current=${season.isCurrent})` : 'no — will be created (is_current=false)'}`)
  console.log(`League "${LEAGUE_NAME}" in DB: ${box ? `yes (id ${box.id})` : 'no — will be created, owned by Anton'}`)
  console.log('\nName → account mapping:')
  for (const p of parsed.players) {
    const target = DEFAULT_ALIASES[p.excelName] ?? p.excelName
    const exists = idByName.has(target)
    const note = target !== p.excelName ? ` (alias → "${target}")` : ''
    console.log(`  ${p.excelName.padEnd(8)}${note} → ${exists ? 'EXISTING account' : 'NEW account will be created'}`)
  }
  const { valid, partial } = countPicks(parsed)
  console.log(`\nPredictions to import: ${valid} complete · ${partial} partial (skipped — engine needs complete sets)`)
  console.log(`Subjective truth ${year}: surprise=${SUBJECTIVE_TRUTH_2025.surpriseConstructorId}/${SUBJECTIVE_TRUTH_2025.surpriseDriverCode}, disappointment=${SUBJECTIVE_TRUTH_2025.disappointmentConstructorId}/${SUBJECTIVE_TRUTH_2025.disappointmentDriverCode}`)
  console.log('\nNo changes written. Re-run without --dry-run to apply.\n')
}

async function apply(parsed: ParsedSeason, year: number): Promise<void> {
  console.log(`\n=== Backfilling season ${year} ===\n`)

  console.log('1/4 Loading reference data from the F1 API…')
  const ref = await backfillSeasonData(year)
  console.log(`   events=${ref.eventsUpserted} sessions=${ref.sessionsUpserted} finished=${ref.sessionsFinished} skipped=${ref.sessionsSkipped} ` +
    `driverStandings=${ref.driverStandings} constructorStandings=${ref.constructorStandings} errors=${ref.errors}`)

  console.log('2/4 Importing The Box picks from the sheet…')
  const imp = await importParsedSeason2025(parsed)
  console.log(`   predictions=${imp.predictionsUpserted} preseasonStandings=${imp.preseasonStandingsUpserted} preseasonPicks=${imp.preseasonPicksUpserted}`)
  if (imp.predictionsSkipped.length) console.log(`   skipped: ${imp.predictionsSkipped.map((s) => `${s.reason}×${s.count}`).join(', ')}`)

  console.log('3/4 Setting after-season subjective truth…')
  await truthRepo.upsertTruth(year, SUBJECTIVE_TRUTH_2025)

  console.log('4/4 Rescoring sessions + preseason…')
  const events = await eventsRepo.listForSeason(year)
  let rescored = 0
  for (const ev of events) {
    for (const s of await sessionsRepo.listForEvent(ev.id)) {
      if ((await resultsRepo.listForSession(s.id)).length === 0) continue
      await rescoreSession(s.id)
      rescored++
    }
  }
  const pre = await rescorePreseasonForSeason(year)
  console.log(`   sessionsRescored=${rescored} preseasonScored=${JSON.stringify(pre)}`)
  console.log(`\nDone. Season ${year} is loaded but NOT current (2026 stays current).\n`)
}

async function main(): Promise<number> {
  const args = process.argv.slice(2)
  const dry = args.includes('--dry-run')
  const positional = args.filter((a) => !a.startsWith('--'))
  const year = positional[0] ? Number(positional[0]) : 2025
  const xlsxPath = positional[1] ?? path.join(os.homedir(), 'Downloads', 'Tippspiel-25.xlsx')
  if (!Number.isFinite(year)) { console.error(`Bad year: ${positional[0]}`); return 2 }
  if (!fs.existsSync(xlsxPath)) { console.error(`File not found: ${xlsxPath}`); return 2 }

  console.log(`Reading ${xlsxPath} (season ${year})`)
  const parsed = year === 2025 ? parseWorkbook2025(XLSX.readFile(xlsxPath)) : (() => { throw new Error(`No parser profile for season ${year}`) })()

  if (dry) await dryRun(parsed, year)
  else await apply(parsed, year)
  return 0
}

main()
  .then(async (code) => { await _resetPoolForTests(); process.exit(code) })
  .catch(async (e) => { console.error(e); await _resetPoolForTests(); process.exit(1) })
