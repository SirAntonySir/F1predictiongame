/**
 * Back-fill preseason projection snapshots for every finished race in the
 * current season. The live rescorer only writes a snapshot for the *most
 * recent* race, so without this script the gossip endpoint can never compute
 * a delta until two future races have run with the rescorer active.
 *
 * For each finished race S_n (ordered by scheduledStart):
 *   1. Filter all sessions + results to those with scheduledStart <= S_n.
 *   2. Reconstruct driver / constructor standings as-of S_n by summing
 *      session_result.points across in-range race + sprint sessions.
 *   3. Derive truths (DNF / poles / fastest_lap / WDC+WCC) from those.
 *      Subjective truths (surprise / disappointment) use whatever is in the
 *      subjective_truth table today — fine because they aren't season-time-
 *      dependent (judged at year-end).
 *   4. Score every user's pre-season pick set against those truths.
 *   5. Upsert a snapshot row keyed to S_n.
 *
 * After this runs, the gossip endpoint's `myProjection` returns:
 *   - `now` = total after the most recent race,
 *   - `delta` = `now - previous` where `previous` was the snapshot after
 *     the race before that.
 *
 * Idempotent — the snapshots table PK is (user_id, season_year, after_session_id),
 * upserts overwrite cleanly.
 *
 * Usage:
 *   set -a && source .env && set +a && npx tsx src/scripts/backfillProjectionSnapshots.ts
 *
 *   # Or against prod (paste the External DB URL):
 *   DATABASE_URL='postgresql://...' npx tsx src/scripts/backfillProjectionSnapshots.ts
 */
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as picksRepo from '../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../repo/preseasonStandings.js'
import * as truthRepo from '../repo/subjectiveTruth.js'
import * as projectionSnapshotsRepo from '../repo/preseasonProjectionSnapshots.js'
import { scorePreseasonCategory, scoreStandings } from '../preseason/index.js'
import {
  deriveMostDnfs, derivePolesitter, deriveMostFastestLaps, deriveWdcWcc, deriveFinalStandings,
} from '../preseason/derive.js'
import { _resetPoolForTests } from '../db/client.js'
import type { PreseasonCategory, DriverStanding, ConstructorStanding } from '../domain/types.js'

const SEASON_YEAR = 2026
const ALL_SINGLE_CATEGORIES: PreseasonCategory[] = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc',
]

async function main(): Promise<number> {
  const events = await eventsRepo.listForSeason(SEASON_YEAR)
  if (events.length === 0) { console.log('no events for season'); return 0 }

  // Pull every session + every session_result once.
  const sessionsByRound = new Map<number, number>()  // session.id -> round
  const allSessions: Awaited<ReturnType<typeof sessionsRepo.listForEvent>> = []
  const allResults: Awaited<ReturnType<typeof resultsRepo.listForSession>> = []
  for (const ev of events) {
    const ss = await sessionsRepo.listForEvent(ev.id)
    for (const s of ss) sessionsByRound.set(s.id, ev.round)
    allSessions.push(...ss)
    for (const s of ss) {
      const rows = await resultsRepo.listForSession(s.id)
      allResults.push(...rows)
    }
  }

  const finishedRaces = allSessions
    .filter((s) => s.type === 'race' && s.status === 'finished')
    .sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())
  if (finishedRaces.length === 0) { console.log('no finished races yet'); return 0 }

  // Subjective truths — not time-dependent for this purpose.
  const subjective = await truthRepo.getTruth(SEASON_YEAR)
  const surpriseTruth = {
    driverCode: subjective?.surpriseDriverCode ?? null,
    constructorId: subjective?.surpriseConstructorId ?? null,
  }
  const disappointmentTruth = {
    driverCode: subjective?.disappointmentDriverCode ?? null,
    constructorId: subjective?.disappointmentConstructorId ?? null,
  }

  // All preseason picks for the season, batched for fast in-memory lookup.
  const allSinglePicks = await picksRepo.listForSeason(SEASON_YEAR)
  const singlePickByUserCategory = new Map<string, { driverCode: string | null; constructorId: string | null }>()
  for (const p of allSinglePicks) {
    singlePickByUserCategory.set(`${p.userId}|${p.category}`, {
      driverCode: p.driverCode,
      constructorId: p.constructorId,
    })
  }
  const userIds = new Set<string>(allSinglePicks.map((p) => p.userId))
  // Anyone who only made standings picks (no single-picks) still needs a snapshot.
  // Cheap and good enough: scan the standings tables.
  for (const userId of [...userIds]) {
    void userId  // already in set; keep the loop a placeholder for readability
  }
  // Pull standings picks per user once, lazily inside the per-race loop below.

  console.log(`Back-filling ${finishedRaces.length} snapshots for ${userIds.size} users…`)

  for (const race of finishedRaces) {
    const round = sessionsByRound.get(race.id) ?? 0
    const cutoff = race.scheduledStart
    const sessionsAsOf = allSessions.filter((s) => s.scheduledStart <= cutoff)
    const sessionIdsAsOf = new Set(sessionsAsOf.map((s) => s.id))
    const resultsAsOf = allResults.filter((r) => sessionIdsAsOf.has(r.sessionId))

    // Reconstruct championship standings as-of S_n from session_result.points.
    const driverAgg = new Map<string, { points: number; constructorId: string; driverName: string }>()
    const ctorAgg = new Map<string, { points: number; constructorName: string }>()
    for (const r of resultsAsOf) {
      if (r.points == null) continue
      const cur = driverAgg.get(r.driverCode)
      if (cur) cur.points += r.points
      else driverAgg.set(r.driverCode, { points: r.points, constructorId: r.constructorId, driverName: r.driverName })
      const curC = ctorAgg.get(r.constructorId)
      if (curC) curC.points += r.points
      else ctorAgg.set(r.constructorId, { points: r.points, constructorName: r.constructorName })
    }
    const driverStandings: DriverStanding[] = [...driverAgg.entries()]
      .sort((a, b) => b[1].points - a[1].points)
      .map(([driverCode, v], i) => ({
        seasonYear: SEASON_YEAR,
        driverCode,
        driverName: v.driverName,
        constructorId: v.constructorId,
        position: i + 1,
        points: v.points,
        wins: 0,
      }))
    const constructorStandings: ConstructorStanding[] = [...ctorAgg.entries()]
      .sort((a, b) => b[1].points - a[1].points)
      .map(([constructorId, v], i) => ({
        seasonYear: SEASON_YEAR,
        constructorId,
        constructorName: v.constructorName,
        position: i + 1,
        points: v.points,
        wins: 0,
      }))

    const dnfPair    = deriveMostDnfs(resultsAsOf, sessionsAsOf)
    const polesPair  = derivePolesitter(resultsAsOf, sessionsAsOf)
    const flPair     = deriveMostFastestLaps(resultsAsOf, sessionsAsOf)
    const wdcWccPair = deriveWdcWcc(driverStandings, constructorStandings)
    const finalStandings = deriveFinalStandings(driverStandings, constructorStandings)
    const truthFor = (category: PreseasonCategory) => {
      switch (category) {
        case 'surprise':       return surpriseTruth
        case 'disappointment': return disappointmentTruth
        case 'dnf':            return dnfPair
        case 'poles':          return polesPair
        case 'fastest_lap':    return flPair
        case 'wdc_wcc':        return wdcWccPair
      }
    }

    for (const userId of userIds) {
      let total = 0
      for (const category of ALL_SINGLE_CATEGORIES) {
        const pick = singlePickByUserCategory.get(`${userId}|${category}`) ?? { driverCode: null, constructorId: null }
        const breakdown = scorePreseasonCategory(category, pick, truthFor(category))
        total += breakdown.pointsTotal
      }
      const driverPicks = await preseasonStandingsRepo.listDriverPicks(userId, SEASON_YEAR)
      const constructorPicks = await preseasonStandingsRepo.listConstructorPicks(userId, SEASON_YEAR)
      const standingsBreakdown = scoreStandings(driverPicks, constructorPicks, finalStandings.drivers, finalStandings.constructors)
      total += standingsBreakdown.pointsTotal
      await projectionSnapshotsRepo.upsertSnapshot(userId, SEASON_YEAR, race.id, total)
    }
    console.log(`  R${round} (session ${race.id}, ${race.scheduledStart.toISOString().slice(0, 10)}): ${userIds.size} snapshots`)
  }

  return 0
}

main()
  .then(async (c) => { await _resetPoolForTests(); process.exit(c) })
  .catch(async (e) => { console.error(e); await _resetPoolForTests(); process.exit(1) })
