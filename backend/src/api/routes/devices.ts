import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'
import * as notificationsRepo from '../../repo/notifications.js'

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

const registerBody = z.object({
  token: z.string().min(1).max(4096),
  platform: z.enum(['ios', 'android']),
  // IANA zone name, e.g. "Europe/Vienna". Optional — quiet hours just won't be
  // honored for this device until one is reported.
  timezone: z.string().min(1).max(64).optional()
})

const unregisterBody = z.object({
  token: z.string().min(1).max(4096)
})

const prefsBody = z.object({
  enabled: z.boolean().optional(),
  quietEnabled: z.boolean().optional(),
  quietStartMin: z.number().int().min(0).max(1439).optional(),
  quietEndMin: z.number().int().min(0).max(1439).optional()
})

export async function registerDeviceRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  // Register or refresh this device's FCM token for the current user. Also
  // syncs the user's timezone onto their preferences so the dispatcher can
  // evaluate quiet hours server-side.
  app.post('/api/devices', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(registerBody, req.body)
    await notificationsRepo.upsertToken({
      userId: u.id,
      token: body.token,
      platform: body.platform,
      timezone: body.timezone ?? null
    })
    if (body.timezone) {
      await notificationsRepo.upsertPref(u.id, { timezone: body.timezone })
    }
    return { ok: true }
  })

  // Drop a token on explicit logout from this device.
  app.delete('/api/devices', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(unregisterBody, req.body)
    await notificationsRepo.deleteToken(u.id, body.token)
    return { ok: true }
  })

  app.get('/api/notification-prefs', async (req) => {
    const u = getCurrentUser(req)
    const pref = await notificationsRepo.getPrefOrDefault(u.id)
    return { prefs: toWire(pref) }
  })

  app.put('/api/notification-prefs', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(prefsBody, req.body)
    const pref = await notificationsRepo.upsertPref(u.id, body)
    return { prefs: toWire(pref) }
  })
}

function toWire(pref: notificationsRepo.NotificationPref) {
  return {
    enabled: pref.enabled,
    quietEnabled: pref.quietEnabled,
    quietStartMin: pref.quietStartMin,
    quietEndMin: pref.quietEndMin,
    timezone: pref.timezone
  }
}
