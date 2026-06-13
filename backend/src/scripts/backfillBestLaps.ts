/**
 * Backfill per-driver best-lap-with-sectors for every already-finished session
 * that has an OpenF1 session key.
 *
 *   DRY_RUN=1 npx tsx src/scripts/backfillBestLaps.ts       # report only
 *   npx tsx src/scripts/backfillBestLaps.ts                  # apply
 *
 * Optional:
 *   LIMIT=20 — cap at the N most-recent finished sessions (default: all).
 *   ONLY_EMPTY=1 — skip sessions that already have rows (default: overwrite).
 *
 * OpenF1 rate-limits aggressively. The OpenF1Client already retries 429 with
 * exponential backoff, but this script also adds a small inter-session
 * cooldown (250ms) to keep the burst rate reasonable.
 *
 * Idempotent: replaceForSession deletes and re-inserts so re-running yields
 * the same data.
 */
import { eq } from 'drizzle-orm'
import { getDb, getPool } from '../db/client.js'
import { sessionBestLap } from '../db/schema.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as bestLapsRepo from '../repo/bestLaps.js'
import { OpenF1Client } from '../openf1/client.js'
import { parseDrivers, parseBestLapsPerDriver } from '../openf1/parsers.js'

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))

async function existingCount(sessionId: number): Promise<number> {
  const db = getDb()
  const rows = await db.select().from(sessionBestLap).where(eq(sessionBestLap.sessionId, sessionId))
  return rows.length
}

async function main(): Promise<number> {
  const dry = !!process.env.DRY_RUN
  const onlyEmpty = !!process.env.ONLY_EMPTY
  const limit = Number(process.env.LIMIT)
  const cap = Number.isFinite(limit) && limit > 0 ? limit : 1000

  const sessions = await sessionsRepo.listRecentFinishedWithOpenF1Key(cap)
  console.log(`Found ${sessions.length} finished sessions with OpenF1 keys${dry ? '  [DRY RUN]' : ''}`)
  if (sessions.length === 0) return 0

  const openf1 = new OpenF1Client()
  let ok = 0, skipped = 0, errors = 0, drivers = 0

  for (const ses of sessions) {
    const key = ses.openf1SessionKey!
    try {
      if (onlyEmpty) {
        const n = await existingCount(ses.id)
        if (n > 0) {
          console.log(`  skip #${ses.id} (${ses.type})  — already has ${n} rows`)
          skipped++
          continue
        }
      }

      const drvRaw = await openf1.getDrivers(key)
      if (!drvRaw) {
        console.log(`  skip #${ses.id} (${ses.type})  — no drivers from OpenF1`)
        skipped++
        continue
      }
      const drv = parseDrivers(drvRaw)
      const lapsRaw = await openf1.getLaps(key)
      const best = parseBestLapsPerDriver(lapsRaw, drv)
      if (best.length === 0) {
        console.log(`  skip #${ses.id} (${ses.type})  — no valid flying laps`)
        skipped++
        continue
      }
      if (!dry) await bestLapsRepo.replaceForSession(ses.id, best)
      drivers += best.length
      ok++
      console.log(`  ✓ #${ses.id} (${ses.type})  — ${best.length} drivers, fastest ${(Math.min(...best.map((b) => b.lapMs)) / 1000).toFixed(3)}s`)
    } catch (err) {
      errors++
      console.error(`  ✗ #${ses.id} (${ses.type})  — ${err instanceof Error ? err.message : err}`)
    }
    await sleep(250)  // light inter-session cooldown
  }

  console.log(`\nDone — wrote ${ok} sessions (${drivers} driver-laps), ${skipped} skipped, ${errors} errors.${dry ? '  [DRY RUN]' : ''}`)
  return errors === 0 ? 0 : 1
}

main()
  .then(async (code) => { await getPool().end(); process.exit(code) })
  .catch(async (e) => {
    console.error('ERROR:', e instanceof Error ? e.message : e)
    try { await getPool().end() } catch { /* noop */ }
    process.exit(1)
  })
