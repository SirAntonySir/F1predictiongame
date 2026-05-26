import * as XLSX from 'xlsx'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as eventsRepo from '../repo/events.js'
import { rescoreSession } from '../scoring/rescorer.js'
import { _resetPoolForTests } from '../db/client.js'
import { parseWorkbook } from './tippspiel/parser.js'
import { importParsedSeason } from './tippspiel/importer.js'
import { buildComparison, formatComparisonTable } from './tippspiel/validator.js'

const DEFAULT_PATH = path.join(os.homedir(), 'Downloads', 'Tippspiel.xlsx')
const SEASON_YEAR  = 2026

async function main(): Promise<number> {
  const arg = process.argv[2]
  const xlsxPath = arg ?? DEFAULT_PATH
  if (!fs.existsSync(xlsxPath)) {
    console.error(`File not found: ${xlsxPath}`)
    return 2
  }
  console.log(`Reading ${xlsxPath}`)
  const wb = XLSX.readFile(xlsxPath)
  const parsed = parseWorkbook(wb, SEASON_YEAR)
  console.log(`Parsed ${parsed.players.length} players for season ${parsed.seasonYear}`)

  const summary = await importParsedSeason(parsed)
  console.log(`Imported: ${summary.predictionsUpserted} predictions, ` +
              `${summary.preseasonPicksUpserted} preseason picks, ` +
              `${summary.preseasonStandingsUpserted} preseason standings sets`)
  if (summary.skippedSessions.length > 0) {
    console.log('Skipped:')
    for (const s of summary.skippedSessions) console.log(`  ${s.reason}: ${s.count}`)
  }

  // Rescore every session in the season that has results
  const events = await eventsRepo.listForSeason(SEASON_YEAR)
  let rescored = 0
  for (const ev of events) {
    const ss = await sessionsRepo.listForEvent(ev.id)
    for (const s of ss) {
      const results = await resultsRepo.listForSession(s.id)
      if (results.length === 0) continue
      await rescoreSession(s.id)
      rescored += 1
    }
  }
  console.log(`Rescored ${rescored} sessions`)

  const comparison = await buildComparison(parsed, summary.userIdByExcelName)
  console.log('')
  console.log(formatComparisonTable(comparison.rows, comparison.events))

  const mismatches = comparison.rows.reduce((acc, r) => {
    return acc + Object.values(r.perEvent).filter((c) => c.hasApp && c.excel !== c.app).length
  }, 0)
  return mismatches === 0 ? 0 : 1
}

main()
  .then(async (code) => { await _resetPoolForTests(); process.exit(code) })
  .catch(async (e) => { console.error(e); await _resetPoolForTests(); process.exit(1) })
