// One-shot: walk every scheduled FP1/FP2/FP3 session for a given year,
// fetch results from OpenF1, and persist. Idempotent — re-runs simply
// replaceForSession with the same rows.
//
//   tsx src/scripts/backfillPractice.ts <year>        # apply
//   tsx src/scripts/backfillPractice.ts <year> --dry  # report only
//
// Use after the `is_current = false` season has already been bootstrapped
// (mapSessionsToOpenF1 must have populated openf1_session_key on the FP
// rows). For 2026 (the live season) this is the case after every regular
// tick cycle.
import { JolpicaClient } from '../jolpica/client.js'
import { OpenF1Client } from '../openf1/client.js'
import { WikipediaClient } from '../wikipedia/client.js'
import { fetchByType, upsertNewDrivers, upsertNewConstructors } from '../crawler/tick.js'
import { mapSessionsToOpenF1 } from '../crawler/openf1Mapping.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import { _resetPoolForTests } from '../db/client.js'

type FpType = 'fp1' | 'fp2' | 'fp3'
const FP_TYPES: ReadonlySet<FpType> = new Set(['fp1', 'fp2', 'fp3'])

async function main() {
  const yearArg = process.argv[2]
  const dryRun = process.argv.includes('--dry') || process.argv.includes('--dry-run')
  if (!yearArg || !/^\d{4}$/.test(yearArg)) {
    console.error('usage: tsx src/scripts/backfillPractice.ts <year> [--dry]')
    process.exit(2)
  }
  const year = Number(yearArg)
  const jolpica = new JolpicaClient()
  const openf1 = new OpenF1Client()
  const wiki = new WikipediaClient()

  // Refresh OpenF1 session-key mapping so any FP row missing a key (e.g.
  // events added since last bootstrap) gets one before we try to fetch.
  console.log(`[${year}] refreshing OpenF1 session-key mapping…`)
  await mapSessionsToOpenF1(year, openf1)

  const events = await eventsRepo.listForSeason(year)
  let attempted = 0
  let persisted = 0
  let skipped = 0
  let errors = 0
  for (const ev of events) {
    const sessions = await sessionsRepo.listForEvent(ev.id)
    for (const ses of sessions) {
      if (!FP_TYPES.has(ses.type as FpType)) continue
      attempted++
      try {
        const out = await fetchByType(jolpica, openf1, ses.type, year, ev.round, ses.openf1SessionKey)
        if (out.rows.length === 0) {
          console.log(`  round=${ev.round} ${ses.type}: no OpenF1 result (key=${ses.openf1SessionKey ?? 'null'})`)
          skipped++
          continue
        }
        if (dryRun) {
          console.log(`  round=${ev.round} ${ses.type}: would persist ${out.rows.length} rows (P1=${out.rows[0]?.driverCode} ${out.rows[0]?.q1 ?? '?'})`)
          persisted++
          continue
        }
        await upsertNewDrivers(out.drivers, wiki)
        await upsertNewConstructors(out.constructors, wiki)
        await resultsRepo.replaceForSession(ses.id, out.rows.map((r) => ({ ...r, sessionId: ses.id })))
        await sessionsRepo.markFinished(ses.id)
        console.log(`  round=${ev.round} ${ses.type}: persisted ${out.rows.length} rows (P1=${out.rows[0]?.driverCode} ${out.rows[0]?.q1 ?? '?'})`)
        persisted++
      } catch (err) {
        errors++
        console.error(`  round=${ev.round} ${ses.type}: ERROR`, err)
      }
    }
  }
  console.log(`\n[${year}] done. attempted=${attempted} ${dryRun ? 'wouldPersist' : 'persisted'}=${persisted} skipped=${skipped} errors=${errors}`)
}

main()
  .then(async () => { await _resetPoolForTests(); process.exit(0) })
  .catch(async (err) => { console.error(err); await _resetPoolForTests(); process.exit(1) })
