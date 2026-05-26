import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook, requireLeagueMember } from '../auth-context.js'
import { buildLeaguePreseasonView } from '../../preseason/projection.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
import * as standingsRepo from '../../repo/standings.js'
import * as picksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../repo/preseasonStandings.js'
import * as truthRepo from '../../repo/subjectiveTruth.js'
import * as scoresRepo from '../../repo/scores.js'
import type { PreseasonCategory } from '../../domain/types.js'

const CATEGORIES: PreseasonCategory[] = ['surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc']

const singlePickBody = z.object({
  driverCode: z.string().min(1).max(10).nullable().optional(),
  constructorId: z.string().min(1).max(50).nullable().optional()
}).refine((b) => (b.driverCode ?? null) !== null || (b.constructorId ?? null) !== null, {
  message: 'at least one of driverCode or constructorId must be provided'
})

const standingsBody = z.object({
  picks: z.array(z.object({
    position: z.number().int().min(1).max(50),
    driverCode: z.string().min(1).max(10).optional(),
    constructorId: z.string().min(1).max(50).optional()
  })).max(50)
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

function parseCategory(raw: string): PreseasonCategory {
  if (!CATEGORIES.includes(raw as PreseasonCategory)) {
    throw new ApiError('BAD_REQUEST', `Unknown category: ${raw}`)
  }
  return raw as PreseasonCategory
}

async function getPreseasonLockTime(seasonYear: number): Promise<Date | null> {
  const ev = await eventsRepo.getByRound(seasonYear, 1)
  if (!ev) return null
  const sessions = await sessionsRepo.listForEvent(ev.id)
  if (sessions.length === 0) return null
  return sessions.sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())[0]!.scheduledStart
}

async function requireQuestionnaireUnlocked(seasonYear: number): Promise<void> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  if (lockAt && lockAt.getTime() <= Date.now()) {
    throw new ApiError('CONFLICT', 'Pre-season questionnaire is locked')
  }
}

async function requireQuestionnaireLocked(seasonYear: number): Promise<void> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  if (!lockAt || lockAt.getTime() > Date.now()) {
    throw new ApiError('FORBIDDEN', 'Other users\' picks are visible only after lock')
  }
}

async function getCurrentSeasonYear(): Promise<number> {
  const cur = await seasonsRepo.getCurrent()
  if (!cur) throw new ApiError('NOT_FOUND', 'No current season')
  return cur.year
}

async function validateSinglePick(seasonYear: number, body: { driverCode?: string | null; constructorId?: string | null }): Promise<void> {
  if (body.driverCode) {
    if (!(await driversRepo.exists(body.driverCode))) throw new ApiError('VALIDATION', `Unknown driver: ${body.driverCode}`)
    if (!(await standingsRepo.driverHasStandingForYear(body.driverCode, seasonYear))) {
      throw new ApiError('VALIDATION', `Driver ${body.driverCode} not in season ${seasonYear}`)
    }
  }
  if (body.constructorId) {
    if (!(await constructorsRepo.exists(body.constructorId))) throw new ApiError('VALIDATION', `Unknown constructor: ${body.constructorId}`)
    if (!(await standingsRepo.constructorHasStandingForYear(body.constructorId, seasonYear))) {
      throw new ApiError('VALIDATION', `Constructor ${body.constructorId} not in season ${seasonYear}`)
    }
  }
}

export async function registerPreseasonRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.get('/api/preseason/my', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const lockAt = await getPreseasonLockTime(year)
    const allPicks = await picksRepo.listForUser(u.id, year)
    const byCategory = new Map(allPicks.map((p) => [p.category, p]))
    const driverPicks = await preseasonStandingsRepo.listDriverPicks(u.id, year)
    const constructorPicks = await preseasonStandingsRepo.listConstructorPicks(u.id, year)
    return {
      seasonYear: year,
      isLocked: lockAt !== null && lockAt.getTime() <= Date.now(),
      locksAt: lockAt,
      surprise:       byCategory.get('surprise')       ?? null,
      disappointment: byCategory.get('disappointment') ?? null,
      dnf:            byCategory.get('dnf')            ?? null,
      poles:          byCategory.get('poles')          ?? null,
      fastest_lap:    byCategory.get('fastest_lap')    ?? null,
      wdc_wcc:        byCategory.get('wdc_wcc')        ?? null,
      standings: {
        drivers: driverPicks,
        constructors: constructorPicks
      }
    }
  })

  app.put<{ Params: { category: string } }>('/api/preseason/:category', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const cat = parseCategory(req.params.category)
    const body = parse(singlePickBody, req.body)
    await requireQuestionnaireUnlocked(year)
    await validateSinglePick(year, body)
    const pick = await picksRepo.upsertPick(u.id, year, cat, {
      driverCode: body.driverCode ?? null,
      constructorId: body.constructorId ?? null
    })
    return { pick }
  })

  app.delete<{ Params: { category: string } }>('/api/preseason/:category', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const cat = parseCategory(req.params.category)
    await requireQuestionnaireUnlocked(year)
    await picksRepo.deletePick(u.id, year, cat)
    return { ok: true }
  })

  app.put('/api/preseason/standings/drivers', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const body = parse(standingsBody, req.body)
    await requireQuestionnaireUnlocked(year)
    const picks: { position: number; entityId: string }[] = body.picks.map((p) => {
      if (!p.driverCode) throw new ApiError('VALIDATION', 'each pick requires driverCode')
      return { position: p.position, entityId: p.driverCode }
    })
    // positions form [1..N]
    const positions = picks.map((p) => p.position).sort((a, b) => a - b)
    for (let i = 0; i < positions.length; i++) {
      if (positions[i] !== i + 1) throw new ApiError('VALIDATION', 'positions must be a contiguous 1..N range')
    }
    const driverSet = new Set(picks.map((p) => p.entityId))
    if (driverSet.size !== picks.length) throw new ApiError('VALIDATION', 'duplicate driver in standings picks')
    for (const p of picks) {
      if (!(await driversRepo.exists(p.entityId))) throw new ApiError('VALIDATION', `Unknown driver: ${p.entityId}`)
      if (!(await standingsRepo.driverHasStandingForYear(p.entityId, year))) {
        throw new ApiError('VALIDATION', `Driver ${p.entityId} not in season ${year}`)
      }
    }
    await preseasonStandingsRepo.replaceDriverPicks(u.id, year, picks)
    return { picks }
  })

  app.put('/api/preseason/standings/constructors', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const body = parse(standingsBody, req.body)
    await requireQuestionnaireUnlocked(year)
    const picks: { position: number; entityId: string }[] = body.picks.map((p) => {
      if (!p.constructorId) throw new ApiError('VALIDATION', 'each pick requires constructorId')
      return { position: p.position, entityId: p.constructorId }
    })
    const positions = picks.map((p) => p.position).sort((a, b) => a - b)
    for (let i = 0; i < positions.length; i++) {
      if (positions[i] !== i + 1) throw new ApiError('VALIDATION', 'positions must be a contiguous 1..N range')
    }
    const teamSet = new Set(picks.map((p) => p.entityId))
    if (teamSet.size !== picks.length) throw new ApiError('VALIDATION', 'duplicate constructor in standings picks')
    for (const p of picks) {
      if (!(await constructorsRepo.exists(p.entityId))) throw new ApiError('VALIDATION', `Unknown constructor: ${p.entityId}`)
      if (!(await standingsRepo.constructorHasStandingForYear(p.entityId, year))) {
        throw new ApiError('VALIDATION', `Constructor ${p.entityId} not in season ${year}`)
      }
    }
    await preseasonStandingsRepo.replaceConstructorPicks(u.id, year, picks)
    return { picks }
  })

  app.delete('/api/preseason/standings/drivers', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    await requireQuestionnaireUnlocked(year)
    await preseasonStandingsRepo.replaceDriverPicks(u.id, year, [])
    return { ok: true }
  })

  app.delete('/api/preseason/standings/constructors', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    await requireQuestionnaireUnlocked(year)
    await preseasonStandingsRepo.replaceConstructorPicks(u.id, year, [])
    return { ok: true }
  })

  app.get<{ Params: { year: string } }>('/api/seasons/:year/preseason-truth', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    await requireQuestionnaireLocked(year)
    const subjective = await truthRepo.getTruth(year)
    return { seasonYear: year, subjective }
  })

  app.get('/api/users/me/preseason-scores', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const scores = await scoresRepo.listPreseasonForUser(u.id, year)
    return { scores, seasonYear: year }
  })

  app.get<{ Params: { id: string } }>('/api/leagues/:id/preseason', async (req) => {
    const u = getCurrentUser(req)
    await requireLeagueMember(req, req.params.id)
    const year = await getCurrentSeasonYear()
    return await buildLeaguePreseasonView(req.params.id, u.id, year)
  })
}
