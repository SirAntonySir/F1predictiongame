/**
 * One-off backfill for qualifying picks that were locked out by the old
 * event-level lock. Resolves the Monaco qualifying session and each user
 * BY NAME, so it runs against any database — just point DATABASE_URL at the
 * target. Uses upsertPredictionWithPicks, which bypasses the route-level
 * lock (intended for a manual correction). Idempotent (re-running overwrites).
 *
 *   DRY_RUN=1 npx tsx src/scripts/addQualiPicks.ts   # preview, no writes
 *   npx tsx src/scripts/addQualiPicks.ts             # apply
 *
 * Aborts (no writes) if any user name or the session is ambiguous / missing.
 */
import { and, eq, ilike, inArray } from 'drizzle-orm'
import { getDb, getPool } from '../db/client.js'
import { user, event, session, driver, season, league, leagueMember } from '../db/schema.js'
import { upsertPredictionWithPicks } from '../repo/predictions.js'
import { picksRequiredFor } from '../scoring/index.js'

const EVENT_MATCH = '%monaco%'
const SESSION_TYPE = 'qualifying' as const
// Disambiguates duplicate display names (e.g. a stray "anton" test account) by
// requiring membership in the real league.
const LEAGUE_NAME = 'The Box'

// Picks are ordered: position 1, then position 2 (qualifying is Top-2,
// order-sensitive in scoring).
const GROUPS: { names: string[]; picks: { position: number; driverCode: string }[] }[] = [
  { names: ['Anton'], picks: [{ position: 1, driverCode: 'ANT' }, { position: 2, driverCode: 'LEC' }] },
  { names: ['Juli', 'Lukas'], picks: [{ position: 1, driverCode: 'LEC' }, { position: 2, driverCode: 'ANT' }] },
  { names: ['Janine', 'Jonas', 'Jan', 'David', 'Jana', 'Simon'], picks: [{ position: 1, driverCode: 'LEC' }, { position: 2, driverCode: 'HAM' }] }
]

async function main() {
  const dry = !!process.env.DRY_RUN
  const db = getDb()

  const [cur] = await db.select().from(season).where(eq(season.isCurrent, true))
  if (!cur) throw new Error('No current season set')

  const sessRows = await db
    .select({ id: session.id, type: session.type, start: session.scheduledStart, evName: event.name })
    .from(session)
    .innerJoin(event, eq(event.id, session.eventId))
    .where(and(eq(session.type, SESSION_TYPE), ilike(event.name, EVENT_MATCH), eq(event.seasonYear, cur.year)))
  if (sessRows.length !== 1) {
    throw new Error(`Expected exactly 1 ${SESSION_TYPE} for "${EVENT_MATCH}" in ${cur.year}, found ${sessRows.length}`)
  }
  const sess = sessRows[0]!
  const required = picksRequiredFor(SESSION_TYPE)
  console.log(`Session #${sess.id}: ${sess.evName} ${sess.type} @ ${sess.start.toISOString()} (requires ${required} picks)`)

  const allCodes = [...new Set(GROUPS.flatMap((g) => g.picks.map((p) => p.driverCode)))]
  const drv = await db.select({ code: driver.code }).from(driver).where(inArray(driver.code, allCodes))
  const known = new Set(drv.map((d) => d.code))
  for (const c of allCodes) if (!known.has(c)) throw new Error(`Unknown driver code: ${c}`)

  const plan: { name: string; userId: string; picks: { position: number; driverCode: string }[] }[] = []
  for (const g of GROUPS) {
    if (g.picks.length !== required) {
      throw new Error(`${SESSION_TYPE} requires ${required} picks; group [${g.names.join(', ')}] has ${g.picks.length}`)
    }
    for (const name of g.names) {
      const rows = await db
        .select({ id: user.id, displayName: user.displayName })
        .from(user)
        .innerJoin(leagueMember, eq(leagueMember.userId, user.id))
        .innerJoin(league, eq(league.id, leagueMember.leagueId))
        .where(and(ilike(user.displayName, name), eq(league.name, LEAGUE_NAME)))
      if (rows.length !== 1) {
        throw new Error(`Expected exactly 1 user "${name}" in league "${LEAGUE_NAME}", found ${rows.length} [${rows.map((r) => r.displayName).join(', ')}]`)
      }
      plan.push({ name: rows[0]!.displayName, userId: rows[0]!.id, picks: g.picks })
    }
  }

  console.log(`\nPlan — ${plan.length} users${dry ? '  [DRY RUN, no writes]' : ''}:`)
  for (const p of plan) {
    console.log(`  ${p.name.padEnd(8)} ${p.picks.map((x) => `P${x.position}=${x.driverCode}`).join('  ')}`)
  }

  if (dry) {
    console.log('\nDry run complete — re-run without DRY_RUN to apply.')
    return
  }

  for (const p of plan) {
    await upsertPredictionWithPicks(p.userId, sess.id, p.picks)
    console.log(`  ✓ ${p.name}`)
  }
  console.log(`\nDone — ${plan.length} predictions upserted for session #${sess.id}.`)
}

main()
  .then(async () => { await getPool().end() })
  .catch(async (e) => { console.error('ERROR:', e instanceof Error ? e.message : e); try { await getPool().end() } catch { /* noop */ } process.exitCode = 1 })
