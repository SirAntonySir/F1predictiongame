import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as usersRepo from '../../repo/users.js'
import * as sessionsRepo from '../../repo/appSessions.js'
import * as leaguesRepo from '../../repo/leagues.js'
import { hashPassword, verifyPassword } from '../../auth/password.js'
import { generateToken, hashToken } from '../../auth/tokens.js'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'

const SLIDE_MS = 90 * 24 * 60 * 60 * 1000

const signupBody = z.object({
  email: z.string().email().trim(),
  password: z.string().min(8),
  displayName: z.string().trim().min(1).max(40)
})

const loginBody = z.object({
  email: z.string().email().trim(),
  password: z.string().min(1)
})

const patchMeBody = z.object({
  displayName: z.string().trim().min(1).max(40).optional()
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) {
    const first = r.error.issues[0]
    throw new ApiError('VALIDATION', first?.message ?? 'Invalid request body')
  }
  return r.data
}

function publicUser(u: { id: string; email: string; displayName: string; createdAt: Date }) {
  return { id: u.id, email: u.email, displayName: u.displayName, createdAt: u.createdAt }
}

async function issueSession(userId: string, userAgent: string | null) {
  const token = generateToken()
  const tokenHash = hashToken(token)
  await sessionsRepo.insertSession({
    userId,
    tokenHash,
    expiresAt: new Date(Date.now() + SLIDE_MS),
    userAgent
  })
  return token
}

export async function registerAuthRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.post('/api/auth/signup', async (req, reply) => {
    const body = parse(signupBody, req.body)
    const email = body.email.toLowerCase()
    const existing = await usersRepo.findByEmailWithSecret(email)
    if (existing) throw new ApiError('CONFLICT', 'Email already registered')

    const passwordHash = await hashPassword(body.password)
    const user = await usersRepo.insertUser({ email, passwordHash, displayName: body.displayName })
    const token = await issueSession(user.id, (req.headers['user-agent'] as string) ?? null)
    reply.send({ user: publicUser(user), token })
  })

  app.post('/api/auth/login', async (req, reply) => {
    const body = parse(loginBody, req.body)
    const email = body.email.toLowerCase()
    const u = await usersRepo.findByEmailWithSecret(email)
    if (!u || !(await verifyPassword(body.password, u.passwordHash))) {
      throw new ApiError('UNAUTHORIZED', 'Invalid email or password')
    }
    const token = await issueSession(u.id, (req.headers['user-agent'] as string) ?? null)
    reply.send({ user: publicUser(u), token })
  })

  app.get('/api/auth/me', async (req) => {
    const u = getCurrentUser(req)
    const leagues = await leaguesRepo.listForUser(u.id)
    return {
      user: publicUser(u),
      leagues: leagues.map((l) => ({ id: l.id, name: l.name, role: l.role }))
    }
  })

  app.patch('/api/auth/me', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(patchMeBody, req.body)
    let user = u
    if (body.displayName !== undefined) {
      user = await usersRepo.updateDisplayName(u.id, body.displayName)
    }
    return { user: publicUser(user) }
  })

  app.post('/api/auth/logout', async (req) => {
    const header = req.headers.authorization!
    const token = header.slice('Bearer '.length).trim()
    const session = await sessionsRepo.findByTokenHash(hashToken(token))
    if (session) await sessionsRepo.deleteById(session.id)
    return { ok: true }
  })
}
