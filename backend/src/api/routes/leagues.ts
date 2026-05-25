import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as members from '../../repo/leagueMembers.js'
import { generateUniqueJoinCode } from '../../auth/joinCodes.js'
import { getCurrentUser, registerAuthHook, requireLeagueMember, requireLeagueOwner } from '../auth-context.js'

const createBody = z.object({ name: z.string().trim().min(1).max(60) })
const patchBody = z.object({ name: z.string().trim().min(1).max(60).optional() })
const joinBody = z.object({ joinCode: z.string().trim().min(1).max(20) })

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

async function leagueViewForCaller(leagueId: string, callerUserId: string) {
  const l = await leaguesRepo.findById(leagueId)
  if (!l) throw new ApiError('NOT_FOUND', 'League not found')
  const memberCount = await leaguesRepo.countMembers(l.id)
  const isOwner = l.ownerUserId === callerUserId
  return {
    id: l.id,
    name: l.name,
    ownerUserId: l.ownerUserId,
    memberCount,
    createdAt: l.createdAt,
    ...(isOwner ? { joinCode: l.joinCode } : {})
  }
}

export async function registerLeagueRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.post('/api/leagues', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(createBody, req.body)

    const existing = await leaguesRepo.listForUser(u.id)
    if (existing.some((l) => l.role === 'owner')) {
      throw new ApiError('CONFLICT', 'You already own a league')
    }

    const joinCode = await generateUniqueJoinCode(async (c) => {
      return (await leaguesRepo.findByJoinCode(c)) !== null
    })
    const l = await leaguesRepo.createLeagueWithOwner({ name: body.name, ownerUserId: u.id, joinCode })
    return { league: await leagueViewForCaller(l.id, u.id) }
  })

  app.get('/api/leagues/mine', async (req) => {
    const u = getCurrentUser(req)
    const list = await leaguesRepo.listForUser(u.id)
    return {
      leagues: list.map((l) => ({
        id: l.id,
        name: l.name,
        ownerUserId: l.ownerUserId,
        role: l.role,
        createdAt: l.createdAt,
        ...(l.role === 'owner' ? { joinCode: l.joinCode } : {})
      }))
    }
  })

  app.get<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    const u = getCurrentUser(req)
    const exists = await leaguesRepo.findById(req.params.id)
    if (!exists) throw new ApiError('NOT_FOUND', 'League not found')
    await requireLeagueMember(req, req.params.id)
    const league = await leagueViewForCaller(req.params.id, u.id)
    const list = await members.listByLeague(req.params.id)
    const ownerId = league.ownerUserId
    return {
      league,
      members: list.map((m) => ({
        userId: m.userId,
        displayName: m.displayName,
        role: m.userId === ownerId ? 'owner' : 'member',
        joinedAt: m.joinedAt
      }))
    }
  })

  app.patch<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    const u = getCurrentUser(req)
    await requireLeagueOwner(req, req.params.id)
    const body = parse(patchBody, req.body)
    if (body.name !== undefined) {
      await leaguesRepo.updateName(req.params.id, body.name)
    }
    return { league: await leagueViewForCaller(req.params.id, u.id) }
  })

  app.post<{ Params: { id: string } }>('/api/leagues/:id/regenerate-code', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    const code = await generateUniqueJoinCode(async (c) => (await leaguesRepo.findByJoinCode(c)) !== null)
    await leaguesRepo.updateJoinCode(req.params.id, code)
    return { joinCode: code }
  })

  app.delete<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    await leaguesRepo.deleteById(req.params.id)
    return { ok: true }
  })

  app.post('/api/leagues/join', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(joinBody, req.body)
    const code = body.joinCode.toUpperCase()
    const l = await leaguesRepo.findByJoinCode(code)
    if (!l) throw new ApiError('NOT_FOUND', 'Unknown join code')
    if (l.ownerUserId === u.id) throw new ApiError('CONFLICT', 'You already own this league')
    if (await members.isMember(l.id, u.id)) throw new ApiError('CONFLICT', 'Already a member')
    await members.add(l.id, u.id)
    return { league: await leagueViewForCaller(l.id, u.id) }
  })

  app.delete<{ Params: { id: string } }>('/api/leagues/:id/members/me', async (req) => {
    const u = getCurrentUser(req)
    const l = await leaguesRepo.findById(req.params.id)
    if (!l) throw new ApiError('NOT_FOUND', 'League not found')
    if (l.ownerUserId === u.id) throw new ApiError('CONFLICT', 'Owner must delete the league instead of leaving')
    if (!(await members.isMember(l.id, u.id))) throw new ApiError('NOT_FOUND', 'Not a member')
    await members.remove(l.id, u.id)
    return { ok: true }
  })

  app.delete<{ Params: { id: string; userId: string } }>('/api/leagues/:id/members/:userId', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    const l = await leaguesRepo.findById(req.params.id)
    if (l!.ownerUserId === req.params.userId) {
      throw new ApiError('BAD_REQUEST', 'Cannot kick the league owner')
    }
    await members.remove(req.params.id, req.params.userId)
    return { ok: true }
  })
}
