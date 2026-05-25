import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { config } from '../../config.js'
import { ApiError } from '../errors.js'
import { JolpicaClient } from '../../jolpica/client.js'
import { WikipediaClient } from '../../wikipedia/client.js'
import { runBootstrap } from '../../crawler/bootstrap.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as truthRepo from '../../repo/subjectiveTruth.js'
import { rescoreSession } from '../../scoring/rescorer.js'
import { rescorePreseasonForSeason } from '../../preseason/rescorer.js'
import type { Scheduler } from '../../crawler/scheduler.js'

export type AdminDeps = {
  scheduler: Scheduler | null
  jolpica?: JolpicaClient
  wiki?: WikipediaClient
}

export async function registerAdminRoutes(app: FastifyInstance, deps: AdminDeps): Promise<void> {
  const jolpica = deps.jolpica ?? new JolpicaClient()
  const wiki = deps.wiki ?? new WikipediaClient()

  // preHandler hook: gate every /admin/* request behind the admin token.
  app.addHook('preHandler', async (req) => {
    if (!req.url.startsWith('/admin/')) return
    const token = req.headers['x-admin-token']
    if (token !== config.adminToken) {
      throw new ApiError('UNAUTHORIZED', 'Invalid admin token')
    }
  })

  app.post('/admin/bootstrap', async () => {
    const cur = await seasonsRepo.getCurrent()
    const year = cur?.year ?? new Date().getUTCFullYear()
    await runBootstrap(jolpica, year)
    return { ok: true, year }
  })

  app.post('/admin/crawl', async () => {
    if (!deps.scheduler) throw new ApiError('INTERNAL', 'Scheduler not available')
    const summary = await deps.scheduler.tickOnce()
    return { ok: true, summary }
  })

  app.post('/admin/refresh-images', async () => {
    const missingDrivers = await driversRepo.listMissingImage()
    for (const d of missingDrivers) {
      const url = await wiki.getImageUrl(d.wikipediaUrl)
      if (url) await driversRepo.setImageUrl(d.code, url)
    }
    const missingCtors = await constructorsRepo.listMissingImage()
    for (const c of missingCtors) {
      const url = await wiki.getImageUrl(c.wikipediaUrl)
      if (url) await constructorsRepo.setImageUrl(c.id, url)
    }
    return {
      ok: true,
      driversAttempted: missingDrivers.length,
      constructorsAttempted: missingCtors.length
    }
  })

  app.post<{ Params: { id: string } }>('/admin/rescore-session/:id', async (req) => {
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const summary = await rescoreSession(id)
    return { ok: true, sessionId: id, ...summary }
  })

  app.post<{ Params: { year: string } }>('/admin/rescore-season/:year', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const evs = await eventsRepo.listForSeason(year)
    let users = 0, totalPoints = 0
    for (const ev of evs) {
      const sessions = await sessionsRepo.listForEvent(ev.id)
      for (const ses of sessions) {
        const summary = await rescoreSession(ses.id)
        users += summary.users
        totalPoints += summary.totalPoints
      }
    }
    return { ok: true, season: year, users, totalPoints }
  })

  const truthBody = z.object({
    surpriseDriverCode: z.string().min(1).max(10).nullable(),
    surpriseConstructorId: z.string().min(1).max(50).nullable(),
    disappointmentDriverCode: z.string().min(1).max(10).nullable(),
    disappointmentConstructorId: z.string().min(1).max(50).nullable()
  })

  app.post<{ Params: { year: string } }>('/admin/seasons/:year/subjective-truth', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const parsed = truthBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')
    await truthRepo.upsertTruth(year, parsed.data)
    const summary = await rescorePreseasonForSeason(year)
    return { ok: true, year, ...summary }
  })

  app.post<{ Params: { year: string } }>('/admin/preseason-rescore/:year', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const summary = await rescorePreseasonForSeason(year)
    return { ok: true, year, ...summary }
  })
}
