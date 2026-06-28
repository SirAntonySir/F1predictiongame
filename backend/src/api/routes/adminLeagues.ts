import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembersRepo from '../../repo/leagueMembers.js'
import { hashPassword } from '../../auth/password.js'
import { generateUniqueJoinCode } from '../../auth/joinCodes.js'

const patchBody = z.object({
  name: z.string().min(1).max(80).optional(),
  password: z.string().min(4).nullable().optional()
})

// Cross-user league administration. Unlike the user-facing /api/leagues routes
// (owner-scoped), these are token-gated and operate on any league.
export async function registerAdminLeagueRoutes(app: FastifyInstance): Promise<void> {
  app.patch<{ Params: { id: string } }>('/admin/leagues/:id', async (req) => {
    const parsed = patchBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')
    if (!(await leaguesRepo.findById(req.params.id))) {
      throw new ApiError('NOT_FOUND', `League ${req.params.id} not found`)
    }
    if (parsed.data.name !== undefined) {
      await leaguesRepo.updateName(req.params.id, parsed.data.name)
    }
    if (parsed.data.password !== undefined) {
      const hash = parsed.data.password === null ? null : await hashPassword(parsed.data.password)
      await leaguesRepo.updatePasswordHash(req.params.id, hash)
    }
    const league = await leaguesRepo.findById(req.params.id)
    return { ok: true, league }
  })

  app.post<{ Params: { id: string } }>('/admin/leagues/:id/regenerate-code', async (req) => {
    if (!(await leaguesRepo.findById(req.params.id))) {
      throw new ApiError('NOT_FOUND', `League ${req.params.id} not found`)
    }
    const code = await generateUniqueJoinCode(async (c) => (await leaguesRepo.findByJoinCode(c)) !== null)
    await leaguesRepo.updateJoinCode(req.params.id, code)
    return { ok: true, joinCode: code }
  })

  app.delete<{ Params: { id: string } }>('/admin/leagues/:id', async (req) => {
    if (!(await leaguesRepo.findById(req.params.id))) {
      throw new ApiError('NOT_FOUND', `League ${req.params.id} not found`)
    }
    await leaguesRepo.deleteById(req.params.id)
    return { ok: true }
  })

  app.delete<{ Params: { id: string; userId: string } }>(
    '/admin/leagues/:id/members/:userId',
    async (req) => {
      const league = await leaguesRepo.findById(req.params.id)
      if (!league) throw new ApiError('NOT_FOUND', `League ${req.params.id} not found`)
      if (req.params.userId === league.ownerUserId) {
        throw new ApiError('CONFLICT', "Can't remove the owner — delete the league instead")
      }
      await leagueMembersRepo.remove(req.params.id, req.params.userId)
      return { ok: true }
    }
  )
}
