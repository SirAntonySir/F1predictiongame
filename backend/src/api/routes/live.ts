import type { FastifyInstance } from 'fastify'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'
import { ApiError } from '../errors.js'
import { config } from '../../config.js'
import { OpenF1Client } from '../../openf1/client.js'
import { parseDrivers } from '../../openf1/parsers.js'
import { parseLivePositions, resolveOpenF1SessionKey } from '../../openf1/live.js'
import { projectTotal } from '../../scoring/project.js'
import { isScorableSessionType } from '../../scoring/index.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as picksRepo from '../../repo/predictionPicks.js'

export type LiveDeps = { openf1?: Pick<OpenF1Client, 'getSessions' | 'getDrivers' | 'getPosition'> }

/// How long a fetched running order is served to other callers. The order is
/// identical for every user/league, and each client polls every ~20s — so N
/// clients cost ~1 upstream OpenF1 round-trip per window instead of N.
export const LIVE_ORDER_TTL_MS = 10_000

export async function registerLiveRoutes(app: FastifyInstance, deps?: LiveDeps): Promise<void> {
  registerAuthHook(app)
  const openf1 = deps?.openf1 ?? new OpenF1Client(config.openf1Base)

  // Per-session cache of the parsed running order. Tiny: at most one session
  // is live at a time, entries expire by TTL, and per-user projections are
  // still computed per request (they're cheap DB reads + math).
  const orderCache = new Map<number, { at: number; order: ReturnType<typeof parseLivePositions> }>()

  app.get<{ Params: { id: string }; Querystring: { leagueId?: string } }>(
    '/api/sessions/:id/live',
    async (req) => {
      const u = getCurrentUser(req)
      const id = Number(req.params.id)
      if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
      const s = await sessionsRepo.getById(id)
      if (!s) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
      if (!isScorableSessionType(s.type)) throw new ApiError('BAD_REQUEST', 'session type is not scorable')

      const asOf = new Date().toISOString()
      if (s.status === 'finished') {
        return { sessionId: id, state: 'final', asOf, order: [], myProjected: null, leagueProjected: [] }
      }

      const key = await resolveOpenF1SessionKey(s, openf1, sessionsRepo.setOpenF1SessionKey)
      if (key == null) {
        return { sessionId: id, state: 'unavailable', asOf, order: [], myProjected: null, leagueProjected: [] }
      }

      const cached = orderCache.get(id)
      let order: ReturnType<typeof parseLivePositions>
      if (cached != null && Date.now() - cached.at < LIVE_ORDER_TTL_MS) {
        order = cached.order
      } else {
        const [rawPos, rawDrv] = await Promise.all([openf1.getPosition(key), openf1.getDrivers(key)])
        order = parseLivePositions(rawPos, parseDrivers(rawDrv))
        orderCache.set(id, { at: Date.now(), order })
      }
      const pastEnd = Date.now() >= s.scheduledEnd.getTime()
      const state = order.length === 0 ? (pastEnd ? 'provisional' : 'pre') : (pastEnd ? 'provisional' : 'live')

      const myPred = await predictionsRepo.getByUserAndSession(u.id, id)
      const myPicks = myPred ? await picksRepo.listForPrediction(myPred.id) : []
      const myProjected = { pointsTotal: projectTotal(s.type, myPicks, order) }

      let leagueProjected: Array<{ userId: string; displayName: string; picks: { position: number; driverCode: string }[]; pointsTotal: number | null }> = []
      const leagueId = req.query.leagueId
      if (leagueId) {
        const members = await predictionsRepo.listLeagueMemberPredictions(leagueId, id)
        leagueProjected = members
          .filter((m) => m.userId !== u.id)
          .map((m) => ({ userId: m.userId, displayName: m.displayName, picks: m.picks, pointsTotal: projectTotal(s.type, m.picks, order) }))
          .sort((a, b) => (b.pointsTotal ?? -1) - (a.pointsTotal ?? -1))
      }

      return { sessionId: id, state, asOf, order, myProjected, leagueProjected }
    }
  )
}
