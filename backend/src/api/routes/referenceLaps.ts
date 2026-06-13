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
import { ApiError } from '../errors.js'
import type { SessionType } from '../../domain/types.js'

type Tier = 'sessionBest' | 'personalBest' | 'neutral'

type LapRow = {
  driverCode: string
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

      const sessionIds = refs.map((r) => r.id)
      const allLaps = await bestLapsRepo.listForSessions(sessionIds)

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
