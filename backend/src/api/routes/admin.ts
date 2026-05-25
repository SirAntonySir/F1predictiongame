import type { FastifyInstance } from 'fastify'
import { config } from '../../config.js'
import { ApiError } from '../errors.js'
import { JolpicaClient } from '../../jolpica/client.js'
import { WikipediaClient } from '../../wikipedia/client.js'
import { runBootstrap } from '../../crawler/bootstrap.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
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
}
