import type { FastifyInstance } from 'fastify'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook, requireLeagueMember } from '../auth-context.js'
import * as scoresRepo from '../../repo/scores.js'
import * as seasonsRepo from '../../repo/seasons.js'
import { seasonFromQuery } from '../season-query.js'

export async function registerLeaderboardRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.get<{ Params: { id: string }; Querystring: { season?: string } }>(
    '/api/leagues/:id/leaderboard',
    async (req) => {
      await requireLeagueMember(req, req.params.id)
      const cur = await seasonsRepo.getCurrent()
      const season = seasonFromQuery(req.query, cur?.year ?? new Date().getUTCFullYear())
      const leaderboard = await scoresRepo.leagueLeaderboard(req.params.id, season)
      return { leaderboard, season }
    }
  )

  app.get<{ Params: { id: string }; Querystring: { season?: string } }>(
    '/api/leagues/:id/leaderboard/sessions',
    async (req) => {
      await requireLeagueMember(req, req.params.id)
      const cur = await seasonsRepo.getCurrent()
      const season = seasonFromQuery(req.query, cur?.year ?? new Date().getUTCFullYear())
      const sessions = await scoresRepo.leagueSessionBreakdown(req.params.id, season)
      return { sessions, season }
    }
  )

  app.get<{ Querystring: { season?: string } }>('/api/users/me/scores', async (req) => {
    const u = getCurrentUser(req)
    const cur = await seasonsRepo.getCurrent()
    const season = seasonFromQuery(req.query, cur?.year ?? new Date().getUTCFullYear())
    const scores = await scoresRepo.listForUser(u.id, season)
    return { scores, season }
  })
}
