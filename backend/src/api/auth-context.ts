import type { FastifyInstance, FastifyRequest } from 'fastify'
import { ApiError } from './errors.js'
import * as usersRepo from '../repo/users.js'
import * as sessionsRepo from '../repo/appSessions.js'
import * as leagueMembers from '../repo/leagueMembers.js'
import * as leaguesRepo from '../repo/leagues.js'
import { hashToken } from '../auth/tokens.js'
import type { User } from '../domain/types.js'

declare module 'fastify' {
  interface FastifyRequest {
    user?: User
  }
}

const SLIDE_MS = 90 * 24 * 60 * 60 * 1000

export function getCurrentUser(req: FastifyRequest): User {
  if (!req.user) throw new ApiError('UNAUTHORIZED', 'Not authenticated')
  return req.user
}

async function authenticate(req: FastifyRequest): Promise<void> {
  const header = req.headers.authorization
  if (!header || !header.startsWith('Bearer ')) {
    throw new ApiError('UNAUTHORIZED', 'Missing bearer token')
  }
  const token = header.slice('Bearer '.length).trim()
  if (!token) throw new ApiError('UNAUTHORIZED', 'Missing bearer token')

  const session = await sessionsRepo.findByTokenHash(hashToken(token))
  if (!session) throw new ApiError('UNAUTHORIZED', 'Invalid token')

  if (session.expiresAt.getTime() < Date.now()) {
    await sessionsRepo.deleteById(session.id)
    throw new ApiError('UNAUTHORIZED', 'Session expired')
  }

  await sessionsRepo.touchSession(session.id, new Date(Date.now() + SLIDE_MS))

  const user = await usersRepo.findById(session.userId)
  if (!user) throw new ApiError('UNAUTHORIZED', 'User no longer exists')
  req.user = user
}

/**
 * Register the bearer-auth preHandler on a route group via app.register prefix.
 * Skips signup/login explicitly.
 */
export function registerAuthHook(app: FastifyInstance): void {
  app.addHook('preHandler', async (req) => {
    const path = req.url.split('?')[0]
    // Unauthenticated public endpoints. change-password is open so the user
    // can reset their password from the login screen (without a session) —
    // the route itself enforces email + current password.
    if (path === '/api/auth/signup' || path === '/api/auth/login' || path === '/api/auth/change-password') return
    await authenticate(req)
  })
}

export async function requireLeagueMember(req: FastifyRequest, leagueId: string): Promise<void> {
  const u = getCurrentUser(req)
  const ok = await leagueMembers.isMember(leagueId, u.id)
  if (!ok) throw new ApiError('FORBIDDEN', 'Not a member of this league')
}

export async function requireLeagueOwner(req: FastifyRequest, leagueId: string): Promise<void> {
  const u = getCurrentUser(req)
  const l = await leaguesRepo.findById(leagueId)
  if (!l) throw new ApiError('NOT_FOUND', 'League not found')
  if (l.ownerUserId !== u.id) throw new ApiError('FORBIDDEN', 'Not the league owner')
}
