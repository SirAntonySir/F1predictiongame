import type { FastifyInstance } from 'fastify'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembersRepo from '../../repo/leagueMembers.js'

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
}
