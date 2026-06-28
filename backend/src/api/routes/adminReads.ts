import type { FastifyInstance } from 'fastify'
import type { Scheduler } from '../../crawler/scheduler.js'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembersRepo from '../../repo/leagueMembers.js'
import * as usersRepo from '../../repo/users.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'

// Read-only admin endpoints. Registered on the root app after
// registerAdminRoutes, so the /admin/* token preHandler defined there gates
// every route here too.
export async function registerAdminReadRoutes(
  app: FastifyInstance,
  deps: { scheduler: Scheduler | null }
): Promise<void> {
  app.get('/admin/leagues', async () => {
    const leagues = await leaguesRepo.listAllWithMeta()
    return { leagues }
  })

  app.get<{ Params: { id: string } }>('/admin/leagues/:id', async (req) => {
    const all = await leaguesRepo.listAllWithMeta()
    const league = all.find((l) => l.id === req.params.id)
    if (!league) throw new ApiError('NOT_FOUND', `League ${req.params.id} not found`)
    const members = await leagueMembersRepo.listByLeagueDetailed(req.params.id)
    return { league, members }
  })

  app.get<{ Querystring: { query?: string; limit?: string; offset?: string } }>(
    '/admin/users',
    async (req) => {
      const limit = Math.min(Number(req.query.limit) || 50, 200)
      const offset = Number(req.query.offset) || 0
      const { rows, total } = await usersRepo.listAllWithMeta({ query: req.query.query, limit, offset })
      return { users: rows, total }
    }
  )

  app.get<{ Params: { id: string } }>('/admin/users/:id', async (req) => {
    const user = await usersRepo.getDetail(req.params.id)
    if (!user) throw new ApiError('NOT_FOUND', `User ${req.params.id} not found`)
    return { user }
  })

  app.get<{ Querystring: { season?: string } }>('/admin/sessions', async (req) => {
    const season = req.query.season ? Number(req.query.season) : undefined
    if (season !== undefined && !Number.isFinite(season)) {
      throw new ApiError('BAD_REQUEST', 'season must be a number')
    }
    const sessions = await sessionsRepo.listAllWithFetchMeta(season)
    return { sessions }
  })

  app.get<{ Querystring: { sessionId?: string; userId?: string; leagueId?: string } }>(
    '/admin/predictions',
    async (req) => {
      const { sessionId, userId, leagueId } = req.query
      if (!sessionId && !userId && !leagueId) {
        throw new ApiError('BAD_REQUEST', 'provide at least one of sessionId, userId, leagueId')
      }
      const predictions = await predictionsRepo.listForAdmin({
        sessionId: sessionId ? Number(sessionId) : undefined,
        userId: userId || undefined,
        leagueId: leagueId || undefined
      })
      return { predictions }
    }
  )

  app.get('/admin/crawl/status', async () => {
    const sched = deps.scheduler?.status() ?? { lastTickAt: null, lastTickStatus: null }
    const candidates = await sessionsRepo.listCandidates()
    const all = await sessionsRepo.listAllWithFetchMeta()
    return {
      lastTickAt: sched.lastTickAt,
      lastTickStatus: sched.lastTickStatus,
      pendingCandidates: candidates.map((c) => ({ id: c.id, type: c.type })),
      provisionalSessions: all
        .filter((s) => s.provisional)
        .map((s) => ({ id: s.id, eventName: s.eventName, type: s.type }))
    }
  })
}
