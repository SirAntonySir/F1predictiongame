import type { FastifyInstance } from 'fastify'
import * as seasonsRepo from '../../repo/seasons.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as resultsRepo from '../../repo/results.js'
import * as standingsRepo from '../../repo/standings.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
import { ApiError } from '../errors.js'

export async function registerPublicRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/seasons/current', async () => {
    const s = await seasonsRepo.getCurrent()
    if (!s) throw new ApiError('NOT_FOUND', 'No current season')
    return s
  })

  app.get('/api/events', async () => {
    const cur = await seasonsRepo.getCurrent()
    if (!cur) return []
    const events = await eventsRepo.listForSeason(cur.year)
    return Promise.all(events.map(async (e) => ({
      ...e,
      sessions: await sessionsRepo.listForEvent(e.id)
    })))
  })

  app.get<{ Params: { round: string } }>('/api/events/:round', async (req) => {
    const cur = await seasonsRepo.getCurrent()
    if (!cur) throw new ApiError('NOT_FOUND', 'No current season')
    const round = Number(req.params.round)
    if (!Number.isFinite(round)) throw new ApiError('BAD_REQUEST', 'round must be a number')
    const ev = await eventsRepo.getByRound(cur.year, round)
    if (!ev) throw new ApiError('NOT_FOUND', `Event ${round} not found`)
    return { ...ev, sessions: await sessionsRepo.listForEvent(ev.id) }
  })

  app.get<{ Params: { id: string } }>('/api/sessions/:id', async (req) => {
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const s = await sessionsRepo.getById(id)
    if (!s) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
    return s
  })

  app.get<{ Params: { id: string } }>('/api/sessions/:id/results', async (req) => {
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    return resultsRepo.listForSession(id)
  })

  app.get('/api/next-session', async () => {
    const s = await sessionsRepo.nextScheduled()
    if (!s) throw new ApiError('NOT_FOUND', 'No upcoming session')
    return s
  })

  app.get('/api/standings/drivers', async () => {
    const cur = await seasonsRepo.getCurrent()
    if (!cur) return []
    const standings = await standingsRepo.listDriverStandings(cur.year)
    return Promise.all(standings.map(async (s) => {
      const d = await driversRepo.getByCode(s.driverCode)
      return { ...s, driver: d ? { ...d, image: d.imageUrlOverride ?? d.headshotUrl ?? d.imageUrl } : null }
    }))
  })

  app.get('/api/standings/constructors', async () => {
    const cur = await seasonsRepo.getCurrent()
    if (!cur) return []
    const standings = await standingsRepo.listConstructorStandings(cur.year)
    return Promise.all(standings.map(async (s) => {
      const c = await constructorsRepo.getById(s.constructorId)
      return { ...s, constructor: c ? { ...c, image: c.imageUrlOverride ?? c.imageUrl } : null }
    }))
  })

  app.get<{ Params: { code: string } }>('/api/drivers/:code', async (req) => {
    const d = await driversRepo.getByCode(req.params.code.toUpperCase())
    if (!d) throw new ApiError('NOT_FOUND', `Driver ${req.params.code} not found`)
    return { ...d, image: d.imageUrlOverride ?? d.headshotUrl ?? d.imageUrl }
  })

  app.get<{ Params: { id: string } }>('/api/constructors/:id', async (req) => {
    const c = await constructorsRepo.getById(req.params.id)
    if (!c) throw new ApiError('NOT_FOUND', `Constructor ${req.params.id} not found`)
    return { ...c, image: c.imageUrlOverride ?? c.imageUrl }
  })
}
