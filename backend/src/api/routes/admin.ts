import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { config } from '../../config.js'
import { ApiError } from '../errors.js'
import { JolpicaClient } from '../../jolpica/client.js'
import { WikipediaClient } from '../../wikipedia/client.js'
import { OpenF1Client } from '../../openf1/client.js'
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
import { parseDrivers as parseOpenF1Drivers } from '../../openf1/parsers.js'

export type AdminDeps = {
  scheduler: Scheduler | null
  jolpica?: JolpicaClient
  wiki?: WikipediaClient
  openf1?: OpenF1Client
}

export async function registerAdminRoutes(app: FastifyInstance, deps: AdminDeps): Promise<void> {
  const jolpica = deps.jolpica ?? new JolpicaClient()
  const wiki = deps.wiki ?? new WikipediaClient()
  const openf1 = deps.openf1 ?? new OpenF1Client()

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
    await runBootstrap(jolpica, year, openf1)
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

  app.post('/admin/refresh-openf1-metadata', async () => {
    const missingDrivers = await driversRepo.listMissingHeadshot()
    const missingCtors = await constructorsRepo.listMissingTeamColour()
    const finished = await sessionsRepo.listRecentFinishedWithOpenF1Key(5)

    let driversUpdated = 0
    let constructorsUpdated = 0
    const driverFilled = new Set<string>()
    const ctorFilled = new Set<string>()

    for (const ses of finished) {
      if (driverFilled.size >= missingDrivers.length && ctorFilled.size >= missingCtors.length) break
      const drvRaw = await openf1.getDrivers(ses.openf1SessionKey!)
      if (!drvRaw) continue
      const oDrv = parseOpenF1Drivers(drvRaw)
      for (const d of oDrv) {
        if (missingDrivers.some((md) => md.code === d.code) && !driverFilled.has(d.code) && d.headshotUrl) {
          await driversRepo.setHeadshotUrl(d.code, d.headshotUrl)
          driverFilled.add(d.code)
          driversUpdated++
        }
        const ctorId = d.teamName.toLowerCase().replace(/\s+/g, '_')
        if (missingCtors.some((mc) => mc.id === ctorId) && !ctorFilled.has(ctorId) && d.teamColour) {
          await constructorsRepo.setTeamColour(ctorId, d.teamColour)
          ctorFilled.add(ctorId)
          constructorsUpdated++
        }
      }
    }

    return { ok: true, driversUpdated, constructorsUpdated }
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

  // Promote a (pre-loaded) season to current. The weekly job pre-loads next
  // year's calendar as non-current; this flips is_current when you're ready.
  app.post<{ Params: { year: string } }>('/admin/seasons/:year/activate', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const loaded = (await seasonsRepo.list()).some((s) => s.year === year)
    if (!loaded) {
      throw new ApiError('NOT_FOUND', `Season ${year} is not loaded yet — it pre-loads automatically once F1 publishes the calendar (or POST /admin/bootstrap to load it now).`)
    }
    await seasonsRepo.upsertSeason({ year, isCurrent: true })
    return { ok: true, activated: year }
  })
}
