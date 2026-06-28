import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as scoresRepo from '../../repo/scores.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as driversRepo from '../../repo/drivers.js'
import { rescoreSession } from '../../scoring/rescorer.js'

const picksBody = z.object({
  picks: z.array(z.object({
    position: z.number().int().min(1).max(20),
    driverCode: z.string().min(1).max(10)
  }))
})

export async function registerAdminPredictionRoutes(app: FastifyInstance): Promise<void> {
  app.delete<{ Params: { userId: string; sessionId: string } }>(
    '/admin/predictions/:userId/:sessionId',
    async (req) => {
      const sessionId = Number(req.params.sessionId)
      if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'sessionId must be a number')
      await predictionsRepo.deleteByUserAndSession(req.params.userId, sessionId)
      await scoresRepo.deleteSessionScore(req.params.userId, sessionId)
      const rescored = await rescoreSession(sessionId)
      return { ok: true, rescored }
    }
  )

  app.put<{ Params: { userId: string; sessionId: string } }>(
    '/admin/predictions/:userId/:sessionId/picks',
    async (req) => {
      const sessionId = Number(req.params.sessionId)
      if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'sessionId must be a number')
      const parsed = picksBody.safeParse(req.body)
      if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')
      if (!(await sessionsRepo.getById(sessionId))) throw new ApiError('NOT_FOUND', `Session ${sessionId} not found`)

      const picks = parsed.data.picks
      // positions must form a contiguous prefix 1..N
      const positions = picks.map((p) => p.position).sort((a, b) => a - b)
      for (let i = 0; i < positions.length; i++) {
        if (positions[i] !== i + 1) throw new ApiError('VALIDATION', `positions must be a prefix 1..${picks.length}`)
      }
      // no duplicate drivers
      if (new Set(picks.map((p) => p.driverCode)).size !== picks.length) {
        throw new ApiError('VALIDATION', 'duplicate driver in picks')
      }
      // each driver must exist
      for (const p of picks) {
        if (!(await driversRepo.exists(p.driverCode))) {
          throw new ApiError('VALIDATION', `Driver ${p.driverCode} does not exist`)
        }
      }

      await predictionsRepo.upsertPredictionWithPicks(req.params.userId, sessionId, picks)
      const rescored = await rescoreSession(sessionId)
      return { ok: true, rescored }
    }
  )
}
