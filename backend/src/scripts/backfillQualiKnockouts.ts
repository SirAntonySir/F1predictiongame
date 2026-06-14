/**
 * Backfill per-knockout best-lap-with-sectors for every already-finished
 * qualifying / sprint-qualifying session that has an OpenF1 session key.
 *
 *   DRY_RUN=1 npx tsx src/scripts/backfillQualiKnockouts.ts       # report only
 *   npx tsx src/scripts/backfillQualiKnockouts.ts                  # apply
 *
 * Optional:
 *   LIMIT=20 — cap at the N most-recent quali sessions (default: 1000).
 *   ONLY_EMPTY=1 — skip quali sessions whose best-lap rows already include
 *                  knockout>0 entries (resumable behavior).
 *
 * Idempotent: replaceForSession deletes and re-inserts.
 */
import { and, eq, gt } from 'drizzle-orm'
import { getDb, getPool } from '../db/client.js'
import { sessionBestLap } from '../db/schema.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as bestLapsRepo from '../repo/bestLaps.js'
import * as resultsRepo from '../repo/results.js'
import { OpenF1Client } from '../openf1/client.js'
import { parseDrivers, parseKnockoutBestLapsPerDriver } from '../openf1/parsers.js'

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))

async function hasKnockoutRows(sessionId: number): Promise<boolean> {
  const db = getDb()
  const rows = await db.select()
    .from(sessionBestLap)
    .where(and(eq(sessionBestLap.sessionId, sessionId), gt(sessionBestLap.knockout, 0)))
  return rows.length > 0
}

async function main(): Promise<number> {
  const dry = !!process.env.DRY_RUN
  const onlyEmpty = !!process.env.ONLY_EMPTY
  const limitEnv = Number(process.env.LIMIT)
  const cap = Number.isFinite(limitEnv) && limitEnv > 0 ? limitEnv : 1000

  const all = await sessionsRepo.listRecentFinishedWithOpenF1Key(cap)
  const sessions = all.filter((s) => s.type === 'qualifying' || s.type === 'sprint_quali')
  console.log(`Found ${sessions.length} finished quali sessions${dry ? '  [DRY RUN]' : ''}`)
  if (sessions.length === 0) return 0

  const openf1 = new OpenF1Client()
  let ok = 0, skipped = 0, errors = 0, total = 0

  for (const ses of sessions) {
    const key = ses.openf1SessionKey!
    try {
      if (onlyEmpty && await hasKnockoutRows(ses.id)) {
        console.log(`  skip #${ses.id} (${ses.type})  — already has knockout rows`)
        skipped++
        continue
      }
      const drvRaw = await openf1.getDrivers(key)
      if (!drvRaw) { console.log(`  skip #${ses.id} — no drivers from OpenF1`); skipped++; continue }
      const drv = parseDrivers(drvRaw)
      const lapsRaw = await openf1.getLaps(key)
      const results = await resultsRepo.listForSession(ses.id)
      if (results.length === 0) { console.log(`  skip #${ses.id} — no session_result rows`); skipped++; continue }
      const best = parseKnockoutBestLapsPerDriver(lapsRaw, drv, results)
      if (best.length === 0) {
        console.log(`  skip #${ses.id} — no q-times matched OpenF1 laps`)
        skipped++
        continue
      }
      if (!dry) await bestLapsRepo.replaceForSession(ses.id, best)
      total += best.length
      ok++
      const byKo = [1, 2, 3].map((k) => best.filter((b) => b.knockout === k).length).join('/')
      console.log(`  ✓ #${ses.id} (${ses.type})  — ${best.length} rows  Q1/Q2/Q3 = ${byKo}`)
    } catch (err) {
      errors++
      console.error(`  ✗ #${ses.id} (${ses.type})  — ${err instanceof Error ? err.message : err}`)
    }
    await sleep(250)
  }

  console.log(`\nDone — wrote ${ok} sessions (${total} rows), ${skipped} skipped, ${errors} errors.${dry ? '  [DRY RUN]' : ''}`)
  return errors === 0 ? 0 : 1
}

main()
  .then(async (code) => { await getPool().end(); process.exit(code) })
  .catch(async (e) => {
    console.error('ERROR:', e instanceof Error ? e.message : e)
    try { await getPool().end() } catch { /* noop */ }
    process.exit(1)
  })
