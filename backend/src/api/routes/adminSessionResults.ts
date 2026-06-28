import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as resultsRepo from '../../repo/results.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
import { rescoreSession } from '../../scoring/rescorer.js'

const patchBody = z.object({
  driverCode: z.string().min(1).max(10).optional(),
  driverName: z.string().min(1).optional(),
  constructorId: z.string().min(1).max(50).optional(),
  constructorName: z.string().min(1).optional(),
  points: z.number().int().nullable().optional(),
  status: z.string().nullable().optional(),
  raceTime: z.string().nullable().optional(),
  q1: z.string().nullable().optional(),
  q2: z.string().nullable().optional(),
  q3: z.string().nullable().optional()
})

const postBody = patchBody.extend({
  position: z.number().int().min(1).max(40),
  driverCode: z.string().min(1).max(10),
  driverName: z.string().min(1),
  constructorId: z.string().min(1).max(50),
  constructorName: z.string().min(1)
})

async function assertFks(driverCode?: string, constructorId?: string): Promise<void> {
  if (driverCode !== undefined && !(await driversRepo.exists(driverCode))) {
    throw new ApiError('VALIDATION', `Driver ${driverCode} does not exist`)
  }
  if (constructorId !== undefined && !(await constructorsRepo.exists(constructorId))) {
    throw new ApiError('VALIDATION', `Constructor ${constructorId} does not exist`)
  }
}

export async function registerAdminSessionResultRoutes(app: FastifyInstance): Promise<void> {
  app.patch<{ Params: { id: string; position: string } }>(
    '/admin/sessions/:id/results/:position',
    async (req) => {
      const id = Number(req.params.id)
      const position = Number(req.params.position)
      if (!Number.isFinite(id) || !Number.isFinite(position)) throw new ApiError('BAD_REQUEST', 'id/position must be numbers')
      const parsed = patchBody.safeParse(req.body)
      if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')

      if (!(await sessionsRepo.getById(id))) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
      if (!(await resultsRepo.getResult(id, position))) throw new ApiError('NOT_FOUND', `Result at position ${position} not found`)
      await assertFks(parsed.data.driverCode, parsed.data.constructorId)

      const result = await resultsRepo.updateResultFields(id, position, parsed.data)
      const rescored = await rescoreSession(id)
      return { ok: true, result, rescored }
    }
  )

  app.post<{ Params: { id: string } }>('/admin/sessions/:id/results', async (req) => {
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const parsed = postBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')

    if (!(await sessionsRepo.getById(id))) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
    if (await resultsRepo.getResult(id, parsed.data.position)) throw new ApiError('CONFLICT', `Position ${parsed.data.position} already exists`)
    await assertFks(parsed.data.driverCode, parsed.data.constructorId)

    const result = await resultsRepo.insertResult({
      sessionId: id,
      position: parsed.data.position,
      driverCode: parsed.data.driverCode,
      driverName: parsed.data.driverName,
      constructorId: parsed.data.constructorId,
      constructorName: parsed.data.constructorName,
      raceTime: parsed.data.raceTime ?? null,
      status: parsed.data.status ?? null,
      points: parsed.data.points ?? null,
      fastestLap: null,
      fastestLapTime: null,
      fastestLapSpeed: null,
      q1: parsed.data.q1 ?? null,
      q2: parsed.data.q2 ?? null,
      q3: parsed.data.q3 ?? null
    })
    const rescored = await rescoreSession(id)
    return { ok: true, result, rescored }
  })

  app.delete<{ Params: { id: string; position: string } }>(
    '/admin/sessions/:id/results/:position',
    async (req) => {
      const id = Number(req.params.id)
      const position = Number(req.params.position)
      if (!Number.isFinite(id) || !Number.isFinite(position)) throw new ApiError('BAD_REQUEST', 'id/position must be numbers')
      if (!(await resultsRepo.getResult(id, position))) throw new ApiError('NOT_FOUND', `Result at position ${position} not found`)
      await resultsRepo.deleteResult(id, position)
      const rescored = await rescoreSession(id)
      return { ok: true, rescored }
    }
  )
}
