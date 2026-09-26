import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'
import * as predictionsRepo from '../repo/predictions.js'

export const JOKERS_PER_SEASON = 3

export type JokerApplySummary = {
  sessionId: number
  /// Number of joker predictions created.
  applied: number
}

/**
 * Auto-spend jokers for a race session that has just locked: every user who
 * locked picks for the previous race but has none for this one gets those
 * picks copied in as a `source='joker'` prediction, up to
 * [JOKERS_PER_SEASON] per user per season. One-shot per session — stamps
 * `jokersAppliedAt` so re-runs are no-ops. Returns null when the session is
 * ineligible (not a race, not locked yet, or already stamped).
 */
export async function applyJokersForSession(sessionId: number, now: Date = new Date()): Promise<JokerApplySummary | null> {
  const s = await sessionsRepo.getById(sessionId)
  if (!s || s.type !== 'race') return null
  if (s.scheduledStart.getTime() > now.getTime()) return null
  if (s.jokersAppliedAt) return null

  const prev = await sessionsRepo.findPreviousRace(sessionId)
  let applied = 0
  if (prev) {
    const ev = await eventsRepo.getById(s.eventId)
    const used = await predictionsRepo.countJokersUsedForSeason(ev!.seasonYear)
    const alreadyPredicted = new Set(
      (await predictionsRepo.listForSessionWithPicks(sessionId)).map((p) => p.userId)
    )
    for (const p of await predictionsRepo.listForSessionWithPicks(prev.id)) {
      if (alreadyPredicted.has(p.userId)) continue
      if (p.picks.length === 0) continue
      if ((used.get(p.userId) ?? 0) >= JOKERS_PER_SEASON) continue
      await predictionsRepo.upsertPredictionWithPicks(p.userId, sessionId, p.picks, { source: 'joker' })
      applied++
    }
  }
  await sessionsRepo.setJokersAppliedAt(sessionId, now)
  return { sessionId, applied }
}

/// How far back a tick will catch up on races that locked while the server
/// was down. Races older than this stay unstamped but are excluded by the
/// query window, so they never fire retroactively.
export const JOKER_CATCHUP_WINDOW_MS = 48 * 60 * 60 * 1000

export type JokerTickSummary = {
  /// Race sessions the pass ran for.
  sessions: number
  /// Joker predictions created across those sessions.
  applied: number
}

/// The every-minute entry point: run the joker pass for every race that
/// locked since the last tick (or during the catch-up window after downtime).
export async function runJokersTick(now: Date = new Date()): Promise<JokerTickSummary> {
  const from = new Date(now.getTime() - JOKER_CATCHUP_WINDOW_MS)
  const pending = await sessionsRepo.listJokerPending(from, now)
  let applied = 0
  for (const s of pending) {
    const summary = await applyJokersForSession(s.id, now)
    if (summary) applied += summary.applied
  }
  return { sessions: pending.length, applied }
}
