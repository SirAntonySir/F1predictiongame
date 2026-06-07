import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as eventsRepo from '../../repo/events.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as picksRepo from '../../repo/predictionPicks.js'
import * as driversRepo from '../../repo/drivers.js'
import * as standingsRepo from '../../repo/standings.js'
import { isScorableSessionType, picksRequiredFor } from '../../scoring/index.js'
import type { SessionType } from '../../domain/types.js'

const pickSchema = z.object({
  position: z.number().int().min(1).max(20),
  driverCode: z.string().min(1).max(10)
})

const putBody = z.object({
  // Empty array is allowed so the caller can lock in with no slots filled.
  picks: z.array(pickSchema).max(20)
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

/**
 * Predictions for a session lock when that session itself is scheduled to
 * start. Each session is independent — the race stays open until the race
 * begins, even after practice and qualifying have already run.
 */
function sessionLocked(s: { scheduledStart: Date }): boolean {
  return s.scheduledStart.getTime() <= Date.now()
}

async function requireSessionUnlocked(sessionId: number) {
  const s = await sessionsRepo.getById(sessionId)
  if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
  if (sessionLocked(s)) {
    throw new ApiError('CONFLICT', 'Predictions for this session are locked')
  }
  return s
}

async function requireSessionLocked(sessionId: number) {
  const s = await sessionsRepo.getById(sessionId)
  if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
  if (!sessionLocked(s)) {
    throw new ApiError('FORBIDDEN', 'Other users\' predictions are visible only after lock')
  }
  return s
}

async function validatePicksForSessionType(sessionType: SessionType, picks: { position: number; driverCode: string }[]) {
  if (!isScorableSessionType(sessionType)) {
    throw new ApiError('VALIDATION', `Session type ${sessionType} is not scorable`)
  }
  const max = picksRequiredFor(sessionType)!
  // Partial picks are allowed (caller may want to lock in with empty slots
  // and fill the rest later). We only enforce the upper bound and that the
  // positions form a contiguous prefix 1..picks.length with no gaps.
  if (picks.length > max) {
    throw new ApiError('VALIDATION', `${sessionType} allows at most ${max} picks, got ${picks.length}`)
  }
  const positions = picks.map((p) => p.position).sort((a, b) => a - b)
  for (let i = 0; i < picks.length; i++) {
    if (positions[i] !== i + 1) {
      throw new ApiError('VALIDATION', `picks.position must be a prefix 1..${picks.length}`)
    }
  }
  const driverSet = new Set(picks.map((p) => p.driverCode))
  if (driverSet.size !== picks.length) {
    throw new ApiError('VALIDATION', 'duplicate driver in picks')
  }
  // All drivers exist and are in the current season
  const cur = await seasonsRepo.getCurrent()
  if (!cur && picks.length > 0) throw new ApiError('VALIDATION', 'No current season')
  for (const p of picks) {
    if (!(await driversRepo.exists(p.driverCode))) {
      throw new ApiError('VALIDATION', `Unknown driver: ${p.driverCode}`)
    }
    if (!(await standingsRepo.driverHasStandingForYear(p.driverCode, cur!.year))) {
      throw new ApiError('VALIDATION', `Driver ${p.driverCode} not in current season`)
    }
  }
}

export async function registerPredictionRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.put<{ Params: { id: string } }>('/api/sessions/:id/my-prediction', async (req) => {
    const u = getCurrentUser(req)
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const body = parse(putBody, req.body)
    const s = await requireSessionUnlocked(sessionId)
    await validatePicksForSessionType(s.type, body.picks)
    const sortedPicks = [...body.picks].sort((a, b) => a.position - b.position)
    await predictionsRepo.upsertPredictionWithPicks(u.id, sessionId, sortedPicks)
    return {
      prediction: {
        sessionId,
        picks: sortedPicks,
        isLocked: false
      }
    }
  })

  app.get<{ Params: { id: string } }>('/api/sessions/:id/my-prediction', async (req) => {
    const u = getCurrentUser(req)
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const s = await sessionsRepo.getById(sessionId)
    if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
    const p = await predictionsRepo.getByUserAndSession(u.id, sessionId)
    if (!p) throw new ApiError('NOT_FOUND', 'No prediction for this session')
    const picks = await picksRepo.listForPrediction(p.id)
    return {
      prediction: {
        sessionId,
        picks,
        updatedAt: p.updatedAt,
        isLocked: sessionLocked(s)
      }
    }
  })

  app.delete<{ Params: { id: string } }>('/api/sessions/:id/my-prediction', async (req) => {
    const u = getCurrentUser(req)
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    await requireSessionUnlocked(sessionId)
    await predictionsRepo.deleteByUserAndSession(u.id, sessionId)
    return { ok: true }
  })

  app.get<{ Params: { id: string } }>('/api/sessions/:id/predictions', async (req) => {
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    await requireSessionLocked(sessionId)
    const list = await predictionsRepo.listForSessionWithPicks(sessionId)
    return { predictions: list }
  })

  app.get('/api/predictions/upcoming', async (req) => {
    const u = getCurrentUser(req)
    const cur = await seasonsRepo.getCurrent()
    if (!cur) return { upcoming: [] }
    const events = await eventsRepo.listForSeason(cur.year)
    const upcoming: any[] = []
    for (const ev of events) {
      const allSessions = await sessionsRepo.listForEvent(ev.id)
      for (const s of allSessions) {
        if (!isScorableSessionType(s.type)) continue
        const myPrediction = await predictionsRepo.getByUserAndSession(u.id, s.id)
        const myPicks = myPrediction ? await picksRepo.listForPrediction(myPrediction.id) : null
        upcoming.push({
          session: { id: s.id, type: s.type },
          event: { id: ev.id, round: ev.round, name: ev.name, country: ev.country },
          picksRequired: picksRequiredFor(s.type)!,
          locksAt: s.scheduledStart,
          isLocked: sessionLocked(s),
          myPicks
        })
      }
    }
    upcoming.sort((a, b) => new Date(a.locksAt).getTime() - new Date(b.locksAt).getTime())
    return { upcoming }
  })
}
