import type { FastifyInstance } from 'fastify'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembersRepo from '../../repo/leagueMembers.js'
import * as usersRepo from '../../repo/users.js'

// Read-only admin endpoints. Registered on the root app after
// registerAdminRoutes, so the /admin/* token preHandler defined there gates
// every route here too.
export async function registerAdminReadRoutes(app: FastifyInstance): Promise<void> {
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
}
