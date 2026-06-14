// GET /api/sessions/:id/reference-laps
//
// For a given prediction session (quali, race, etc), returns up to 3 most
// recently-finished sessions from the same event, each with per-driver best
// lap (+ sector durations + tier flags) so the predict-screen can render
// F1-style sector-color reference cards.
//
// Tiers (per sector):
//   - sessionBest: this driver had the fastest S1/S2/S3 in this reference
//                  session (violet on the broadcast).
//   - personalBest: this driver's fastest S1/S2/S3 *across* the reference
//                   sessions in scope (green).
//   - neutral: neither.
// lapTier: the strongest tier the driver achieved in any sector for that lap.
import type { FastifyInstance } from 'fastify'
import * as sessionsRepo from '../../repo/sessions.js'
import * as bestLapsRepo from '../../repo/bestLaps.js'
import * as resultsRepo from '../../repo/results.js'
import { ApiError } from '../errors.js'
import type { SessionType } from '../../domain/types.js'

type Tier = 'sessionBest' | 'personalBest' | 'neutral'

type LapRow = {
  driverCode: string
  constructorId: string | null
  lapMs: number
  lapTier: Tier
  s1Ms: number | null; s1Tier: Tier
  s2Ms: number | null; s2Tier: Tier
  s3Ms: number | null; s3Tier: Tier
  lapNumber: number | null
}

type ReferenceSession = {
  sessionId: number
  type: SessionType
  label: string
  laps: LapRow[]
}

const LABEL: Record<SessionType, string> = {
  fp1: 'FP1', fp2: 'FP2', fp3: 'FP3',
  qualifying: 'Q', sprint_quali: 'SQ', sprint: 'SPR', race: 'R'
}

const KNOCKOUT_LABEL_PREFIX: Partial<Record<SessionType, string>> = {
  qualifying: 'Q',
  sprint_quali: 'SQ'
}

/// Inverse of openf1/parsers.formatDuration. Accepts "M:SS.mmm" (e.g.
/// "1:30.500") and "SS.mmm" (no minute). Returns null for malformed input.
function parseLapMs(s: string | null): number | null {
  if (s == null) return null
  const m = /^(?:(\d+):)?(\d{1,2})\.(\d{1,3})$/.exec(s.trim())
  if (!m) return null
  const minutes = m[1] ? Number(m[1]) : 0
  const secs = Number(m[2])
  const ms = Number(m[3]!.padEnd(3, '0').slice(0, 3))
  return minutes * 60_000 + secs * 1_000 + ms
}

const TIER_RANK: Record<Tier, number> = { sessionBest: 2, personalBest: 1, neutral: 0 }
const topTier = (a: Tier, b: Tier): Tier => (TIER_RANK[a] >= TIER_RANK[b] ? a : b)

/// Pick the reference sessions for a predict session: all sessions of the same
/// event that are finished, exclude the predict session itself, take the most
/// recent three by scheduled start.
async function pickReferenceSessions(predictSessionId: number) {
  const predict = await sessionsRepo.getById(predictSessionId)
  if (!predict) throw new ApiError('NOT_FOUND', `Session ${predictSessionId} not found`)
  const all = await sessionsRepo.listForEvent(predict.eventId)
  const refs = all
    .filter((s) => s.id !== predict.id && s.status === 'finished')
    .sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())
  const last3 = refs.slice(-3)
  return { predict, refs: last3 }
}

export async function registerReferenceLapsRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Params: { id: string } }>(
    '/api/sessions/:id/reference-laps',
    async (req) => {
      const id = Number(req.params.id)
      if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
      const { predict, refs } = await pickReferenceSessions(id)
      if (refs.length === 0) {
        return { predictSessionId: predict.id, predictSessionType: predict.type, references: [] }
      }

      // Qualifying breakdown: when a (sprint-)quali is among the references it
      // carries more predictive signal as three knockout segments than as one
      // best-of-session column, so we expand it into Q1/Q2/Q3 (or SQ1/SQ2/SQ3)
      // and drop the other references — keeps the predict-screen header at
      // ≤3 columns. Lap-time strings live in session_result.q1/q2/q3; we don't
      // have per-knockout sectors so the expanded entries are lap-only.
      const knockoutRef = refs.find((r) => KNOCKOUT_LABEL_PREFIX[r.type] != null)
      if (knockoutRef != null) {
        const prefix = KNOCKOUT_LABEL_PREFIX[knockoutRef.type]!
        // Prefer knockout-tagged best-lap rows when ingestion has populated
        // them (post-backfill quali): three rows per driver with real sector
        // splits, full session/personal-best tiering. Falls back to the
        // session_result.q1/q2/q3 lap-only path when no knockout rows exist
        // (pre-backfill quali, or session_best_lap was never populated).
        const knockoutLaps = (await bestLapsRepo.listForSessions([knockoutRef.id]))
          .filter((r) => r.knockout >= 1 && r.knockout <= 3)
        const resultRows = await resultsRepo.listForSession(knockoutRef.id)
        const constructorByDriver = new Map<string, string>()
        for (const r of resultRows) {
          if (!constructorByDriver.has(r.driverCode)) constructorByDriver.set(r.driverCode, r.constructorId)
        }

        if (knockoutLaps.length > 0) {
          // Personal-best per (driver, sector) across the three knockout
          // segments — mirrors the session-level pb map used by the fallthrough
          // path, but scoped to this single quali session.
          const pb = new Map<string, { s1: number | null; s2: number | null; s3: number | null }>()
          for (const r of knockoutLaps) {
            const e = pb.get(r.driverCode) ?? { s1: null, s2: null, s3: null }
            if (r.s1Ms != null) e.s1 = e.s1 == null ? r.s1Ms : Math.min(e.s1, r.s1Ms)
            if (r.s2Ms != null) e.s2 = e.s2 == null ? r.s2Ms : Math.min(e.s2, r.s2Ms)
            if (r.s3Ms != null) e.s3 = e.s3 == null ? r.s3Ms : Math.min(e.s3, r.s3Ms)
            pb.set(r.driverCode, e)
          }
          const segments: ReferenceSession[] = [1, 2, 3].map((k) => {
            const rowsK = knockoutLaps.filter((r) => r.knockout === k)
            const sb = { s1: null as number | null, s2: null as number | null, s3: null as number | null }
            for (const r of rowsK) {
              if (r.s1Ms != null) sb.s1 = sb.s1 == null ? r.s1Ms : Math.min(sb.s1, r.s1Ms)
              if (r.s2Ms != null) sb.s2 = sb.s2 == null ? r.s2Ms : Math.min(sb.s2, r.s2Ms)
              if (r.s3Ms != null) sb.s3 = sb.s3 == null ? r.s3Ms : Math.min(sb.s3, r.s3Ms)
            }
            const laps: LapRow[] = rowsK.map((r) => {
              const pbE = pb.get(r.driverCode)!
              const tier = (cur: number | null, s: number | null, p: number | null): Tier => {
                if (cur == null) return 'neutral'
                if (s != null && cur === s) return 'sessionBest'
                if (p != null && cur === p) return 'personalBest'
                return 'neutral'
              }
              const s1Tier = tier(r.s1Ms, sb.s1, pbE.s1)
              const s2Tier = tier(r.s2Ms, sb.s2, pbE.s2)
              const s3Tier = tier(r.s3Ms, sb.s3, pbE.s3)
              return {
                driverCode: r.driverCode,
                constructorId: constructorByDriver.get(r.driverCode) ?? null,
                lapMs: r.lapMs,
                lapTier: topTier(topTier(s1Tier, s2Tier), s3Tier),
                s1Ms: r.s1Ms, s1Tier,
                s2Ms: r.s2Ms, s2Tier,
                s3Ms: r.s3Ms, s3Tier,
                lapNumber: r.lapNumber
              }
            })
            laps.sort((a, b) => a.lapMs - b.lapMs)
            return { sessionId: knockoutRef.id, type: knockoutRef.type, label: `${prefix}${k}`, laps }
          })
          return { predictSessionId: predict.id, predictSessionType: predict.type, references: segments }
        }

        const segments: ReferenceSession[] = [1, 2, 3].map((k) => {
          const laps: LapRow[] = []
          for (const r of resultRows) {
            const raw = k === 1 ? r.q1 : k === 2 ? r.q2 : r.q3
            const lapMs = parseLapMs(raw)
            if (lapMs == null) continue
            laps.push({
              driverCode: r.driverCode,
              constructorId: r.constructorId,
              lapMs,
              lapTier: 'neutral',
              s1Ms: null, s1Tier: 'neutral',
              s2Ms: null, s2Tier: 'neutral',
              s3Ms: null, s3Tier: 'neutral',
              lapNumber: null
            })
          }
          laps.sort((a, b) => a.lapMs - b.lapMs)
          return { sessionId: knockoutRef.id, type: knockoutRef.type, label: `${prefix}${k}`, laps }
        })
        return { predictSessionId: predict.id, predictSessionType: predict.type, references: segments }
      }

      const sessionIds = refs.map((r) => r.id)
      const allLaps = await bestLapsRepo.listForSessions(sessionIds)

      // Driver → constructor lookup, built from session_result rows of the
      // reference sessions. Lets the frontend show team color for drivers who
      // ran practice but weren't classified in the most recent finished race
      // (DNF, reserves, etc) — those would otherwise fall back to neutral
      // grey on the predict screen.
      const constructorByDriver = new Map<string, string>()
      for (const sid of sessionIds) {
        const rows = await resultsRepo.listForSession(sid)
        for (const r of rows) {
          // First-seen wins; iteration order is chronological so the earliest
          // appearance of the driver this weekend defines their team. Mid-
          // weekend team swaps don't happen in modern F1.
          if (!constructorByDriver.has(r.driverCode)) {
            constructorByDriver.set(r.driverCode, r.constructorId)
          }
        }
      }

      // Personal-best per (driver, sector) across all reference sessions in
      // scope. Compute once up front so per-row tiering is O(1).
      const pb = new Map<string, { s1: number | null; s2: number | null; s3: number | null }>()
      for (const l of allLaps) {
        const e = pb.get(l.driverCode) ?? { s1: null, s2: null, s3: null }
        if (l.s1Ms != null) e.s1 = e.s1 == null ? l.s1Ms : Math.min(e.s1, l.s1Ms)
        if (l.s2Ms != null) e.s2 = e.s2 == null ? l.s2Ms : Math.min(e.s2, l.s2Ms)
        if (l.s3Ms != null) e.s3 = e.s3 == null ? l.s3Ms : Math.min(e.s3, l.s3Ms)
        pb.set(l.driverCode, e)
      }

      const out: ReferenceSession[] = []
      for (const ref of refs) {
        const lapsInSession = allLaps.filter((l) => l.sessionId === ref.id)
        // Session-best per sector within this reference session.
        const sb = { s1: null as number | null, s2: null as number | null, s3: null as number | null }
        for (const l of lapsInSession) {
          if (l.s1Ms != null) sb.s1 = sb.s1 == null ? l.s1Ms : Math.min(sb.s1, l.s1Ms)
          if (l.s2Ms != null) sb.s2 = sb.s2 == null ? l.s2Ms : Math.min(sb.s2, l.s2Ms)
          if (l.s3Ms != null) sb.s3 = sb.s3 == null ? l.s3Ms : Math.min(sb.s3, l.s3Ms)
        }

        const laps: LapRow[] = lapsInSession.map((l) => {
          const pbEntry = pb.get(l.driverCode)!
          const tier = (
            cur: number | null,
            sBest: number | null,
            pBest: number | null
          ): Tier => {
            if (cur == null) return 'neutral'
            if (sBest != null && cur === sBest) return 'sessionBest'
            if (pBest != null && cur === pBest) return 'personalBest'
            return 'neutral'
          }
          const s1Tier = tier(l.s1Ms, sb.s1, pbEntry.s1)
          const s2Tier = tier(l.s2Ms, sb.s2, pbEntry.s2)
          const s3Tier = tier(l.s3Ms, sb.s3, pbEntry.s3)
          return {
            driverCode: l.driverCode,
            constructorId: constructorByDriver.get(l.driverCode) ?? null,
            lapMs: l.lapMs,
            lapTier: topTier(topTier(s1Tier, s2Tier), s3Tier),
            s1Ms: l.s1Ms, s1Tier,
            s2Ms: l.s2Ms, s2Tier,
            s3Ms: l.s3Ms, s3Tier,
            lapNumber: l.lapNumber
          }
        })
        // Fastest lap first.
        laps.sort((a, b) => a.lapMs - b.lapMs)

        out.push({ sessionId: ref.id, type: ref.type, label: LABEL[ref.type], laps })
      }

      return { predictSessionId: predict.id, predictSessionType: predict.type, references: out }
    }
  )
}
