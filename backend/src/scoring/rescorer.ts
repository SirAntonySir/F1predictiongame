import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'
import * as resultsRepo from '../repo/results.js'
import * as predictionsRepo from '../repo/predictions.js'
import * as scoresRepo from '../repo/scores.js'
import * as standingsRepo from '../repo/standings.js'
import { scoreSession, isScorableSessionType } from './index.js'
import type { Finisher } from './types.js'

export type RescoreSummary = { users: number; totalPoints: number }

/**
 * Recompute and upsert scores for every prediction on this session.
 * No-op if the session type isn't scorable or no results exist yet.
 *
 * To enable the team-bonus rule for picks where the P1 driver DNF'd (and thus
 * doesn't appear in `session_result`), we score twice:
 *   1) with REAL finishers only — authoritative for perPosition (a DNF'd pick
 *      must score 0, not a wrongPos +1).
 *   2) with REAL finishers + synthetic high-position entries from standings —
 *      lets the scoring rule discover the picked driver's team and apply the
 *      team bonus when their teammate won.
 * We keep perPosition from (1) and teamBonus from (2).
 */
export async function rescoreSession(sessionId: number): Promise<RescoreSummary> {
  const ses = await sessionsRepo.getById(sessionId)
  if (!ses) return { users: 0, totalPoints: 0 }
  if (!isScorableSessionType(ses.type)) return { users: 0, totalPoints: 0 }

  const resultRows = await resultsRepo.listForSession(sessionId)
  if (resultRows.length === 0) return { users: 0, totalPoints: 0 }

  const ev = await eventsRepo.getById(ses.eventId)
  if (!ev) return { users: 0, totalPoints: 0 }

  const realFinishers: Finisher[] = resultRows.map((r) => ({
    position: r.position,
    driverCode: r.driverCode,
    constructorId: r.constructorId
  }))
  const finisherCodes = new Set(realFinishers.map((f) => f.driverCode))
  const standings = await standingsRepo.listDriverStandings(ev.seasonYear)
  // Synthetic entries: high positions that never collide with real picks (1..max-grid),
  // used solely so the scoring rule can look up the picked driver's team for the team bonus.
  const synthetic: Finisher[] = standings
    .filter((s) => !finisherCodes.has(s.driverCode))
    .map((s, i) => ({
      position: 1000 + i,
      driverCode: s.driverCode,
      constructorId: s.constructorId
    }))
  const augmentedFinishers: Finisher[] = [...realFinishers, ...synthetic]

  const predictions = await predictionsRepo.listForSessionWithPicks(sessionId)
  let totalPoints = 0
  for (const p of predictions) {
    if (p.picks.length === 0) continue
    let real, augmented
    try {
      real = scoreSession(ses.type, p.picks, realFinishers)
      augmented = scoreSession(ses.type, p.picks, augmentedFinishers)
    } catch {
      continue  // skip predictions with wrong-shape picks (shouldn't happen with route-level validation)
    }
    // perPosition from real (DNF picks score 0, not wrongPos); teamBonus from augmented (uses standings).
    const breakdown = {
      perPosition: real.perPosition,
      teamBonus: augmented.teamBonus,
      rule: real.rule
    }
    const pts = breakdown.perPosition.reduce((s, x) => s + x.points, 0) + breakdown.teamBonus.points
    await scoresRepo.upsertScore(p.userId, sessionId, pts, breakdown)
    totalPoints += pts
  }

  return { users: predictions.length, totalPoints }
}
