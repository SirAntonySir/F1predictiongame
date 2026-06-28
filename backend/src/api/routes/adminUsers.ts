import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as usersRepo from '../../repo/users.js'
import { hashPassword } from '../../auth/password.js'

const patchBody = z.object({
  displayName: z.string().min(1).max(80).optional(),
  email: z.string().email().optional()
})
const pwBody = z.object({ password: z.string().min(8) })

export async function registerAdminUserRoutes(app: FastifyInstance): Promise<void> {
  app.patch<{ Params: { id: string } }>('/admin/users/:id', async (req) => {
    const parsed = patchBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')
    if (!(await usersRepo.findById(req.params.id))) throw new ApiError('NOT_FOUND', `User ${req.params.id} not found`)
    if (parsed.data.email !== undefined) {
      const existing = await usersRepo.findByEmailWithSecret(parsed.data.email)
      if (existing && existing.id !== req.params.id) throw new ApiError('CONFLICT', 'Email already in use')
      await usersRepo.updateEmail(req.params.id, parsed.data.email)
    }
    if (parsed.data.displayName !== undefined) {
      await usersRepo.updateDisplayName(req.params.id, parsed.data.displayName)
    }
    const user = await usersRepo.findById(req.params.id)
    return { ok: true, user }
  })

  app.post<{ Params: { id: string } }>('/admin/users/:id/set-password', async (req) => {
    const parsed = pwBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')
    if (!(await usersRepo.findById(req.params.id))) throw new ApiError('NOT_FOUND', `User ${req.params.id} not found`)
    await usersRepo.updatePasswordHash(req.params.id, await hashPassword(parsed.data.password))
    return { ok: true }
  })

  app.delete<{ Params: { id: string } }>('/admin/users/:id', async (req) => {
    if (!(await usersRepo.findById(req.params.id))) throw new ApiError('NOT_FOUND', `User ${req.params.id} not found`)
    try {
      await usersRepo.deleteById(req.params.id)
    } catch {
      // Most user FKs cascade, but prediction_import.uploaded_by / prediction.imported_by
      // do not — deleting an importer hits a FK violation. Surface it cleanly.
      throw new ApiError('CONFLICT', "Couldn't delete — the user has protected records (e.g. uploaded imports). Reassign or remove those first.")
    }
    return { ok: true }
  })
}
