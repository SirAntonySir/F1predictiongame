/// League-owner JSON import endpoints.
///
///   GET  /api/leagues/:leagueId/imports/schema?season=YYYY   -- template
///   POST /api/leagues/:leagueId/imports?dryRun=1              -- preview
///   POST /api/leagues/:leagueId/imports                       -- apply
///   GET  /api/leagues/:leagueId/imports                       -- audit list
///
/// Designed for two flows:
///   - new member joins mid-season and the owner backfills their predictions,
///   - owner imports a historical season that was played in another app.
///
/// Two-phase apply:
///   - dryRun mode runs the same validation + planning as a real apply but
///     writes nothing. Returns applied/overwrite/skipped lists + per-member
///     score preview so the owner can see exactly what the upload would do.
///   - real apply refuses to write rows that would overwrite existing in-app
///     picks unless body.overwrite=true. The dryRun lets the UI surface that
///     warning and toggle the flag explicitly.
///
/// All endpoints owner-only (audit list is owner+member). Cross-league writes
/// are impossible: every userId must be a current member of the URL leagueId,
/// every sessionId must belong to an event in the requested season.
import { eq, inArray } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { getCurrentUser, requireLeagueOwner, requireLeagueMember, registerAuthHook } from '../auth-context.js'
import { ApiError } from '../errors.js'
import { getDb } from '../../db/client.js'
import { predictionImport, prediction, user as userTable } from '../../db/schema.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembers from '../../repo/leagueMembers.js'
import * as driversRepo from '../../repo/drivers.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as predictionPicksRepo from '../../repo/predictionPicks.js'
import * as resultsRepo from '../../repo/results.js'
import * as preseasonPicksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandings from '../../repo/preseasonStandings.js'
import { picksRequiredFor, scoreSession } from '../../scoring/index.js'
import { rescoreSession } from '../../scoring/rescorer.js'
import { rescorePreseasonForSeason } from '../../preseason/rescorer.js'
import type { SessionType, SessionResultRow } from '../../domain/types.js'
import type { Finisher } from '../../scoring/types.js'

const SCHEMA_VERSION = 1
const MAX_BODY_BYTES = 256 * 1024
const MAX_PREDICTIONS = 5000

// ---- Zod input schema --------------------------------------------------------

const PreseasonCategoryZ = z.enum(['surprise','disappointment','dnf','poles','fastest_lap','wdc_wcc'])

const ImportBody = z.object({
  schemaVersion: z.literal(SCHEMA_VERSION),
  league: z.object({ id: z.string().uuid(), name: z.string() }),
  seasonYear: z.number().int(),
  overwrite: z.boolean().default(false),
  predictions: z.array(z.object({
    userId: z.string().uuid(),
    sessionId: z.number().int(),
    picks: z.array(z.object({
      position: z.number().int().positive(),
      driverCode: z.string()
    })).min(1)
  })).max(MAX_PREDICTIONS),
  preseason: z.object({
    picks: z.array(z.object({
      userId: z.string().uuid(),
      category: PreseasonCategoryZ,
      driverCode: z.string().optional(),
      constructorId: z.string().optional()
    })).max(500).optional(),
    standings: z.array(z.object({
      userId: z.string().uuid(),
      drivers: z.array(z.string()).optional(),
      constructors: z.array(z.string()).optional()
    })).max(500).optional()
  }).optional()
}).strict()

type ImportBodyT = z.infer<typeof ImportBody>

type Pick = { position: number; driverCode: string }
type PredictionPlanItem = {
  userId: string
  sessionId: number
  sessionType: SessionType
  eventName: string
  round: number
  picks: Pick[]
  /// 'app' = existing in-app pick will be replaced.
  /// 'import' = previous import row will be replaced (no warning needed).
  /// null = brand-new row.
  conflictsWith: 'app' | 'import' | null
  /// Points the picks WOULD score, given the session's current results. Null
  /// if the session has no results (race not run yet, etc).
  previewPoints: number | null
}
type SkipItem = { kind: string; userId?: string; sessionId?: number; category?: string; reason: string }

// ---- Helpers -----------------------------------------------------------------

const isScorable = (t: SessionType) => picksRequiredFor(t) !== null

function finishersFor(results: SessionResultRow[]): Finisher[] {
  // The scoring engine asks for {position, driverCode, constructorId} per
  // finisher. SessionResultRow has all three.
  return results.map((r) => ({
    position: r.position,
    driverCode: r.driverCode,
    constructorId: r.constructorId
  }))
}

function totalOf(bd: { perPosition: { points: number }[]; teamBonus: { points: number } }): number {
  return bd.perPosition.reduce((a, p) => a + p.points, 0) + bd.teamBonus.points
}

export async function registerImportsRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  // ---- GET schema template -------------------------------------------------
  app.get<{ Params: { leagueId: string }; Querystring: { season?: string } }>(
    '/api/leagues/:leagueId/imports/schema',
    async (req, reply) => {
      const { leagueId } = req.params
      await requireLeagueOwner(req, leagueId)

      const seasonYear = Number(req.query.season)
      if (!Number.isFinite(seasonYear)) {
        throw new ApiError('BAD_REQUEST', 'season query param required (year)')
      }
      const season = await seasonsRepo.getByYear(seasonYear)
      if (!season) throw new ApiError('NOT_FOUND', `Season ${seasonYear} not bootstrapped`)

      const league = await leaguesRepo.findById(leagueId)
      if (!league) throw new ApiError('NOT_FOUND', 'League not found')

      const members = await leagueMembers.listByLeague(leagueId)
      const events = await eventsRepo.listForSeason(seasonYear)
      const sessions: {
        sessionId: number; round: number; eventName: string; type: SessionType;
        scheduledStart: string; picksRequired: number
      }[] = []
      for (const ev of events) {
        const ss = await sessionsRepo.listForEvent(ev.id)
        for (const s of ss) {
          if (!isScorable(s.type)) continue
          sessions.push({
            sessionId: s.id,
            round: ev.round,
            eventName: ev.name,
            type: s.type,
            scheduledStart: s.scheduledStart.toISOString(),
            picksRequired: picksRequiredFor(s.type)!
          })
        }
      }
      const drivers = (await driversRepo.listAll()).map((d) => d.code).sort()
      const me = getCurrentUser(req)

      const filename = `f1pg-import-${slug(league.name)}-${seasonYear}.json`
      reply.header('Content-Disposition', `attachment; filename="${filename}"`)
      reply.type('application/json')
      return {
        schemaVersion: SCHEMA_VERSION,
        league: { id: league.id, name: league.name },
        seasonYear,
        generatedAt: new Date().toISOString(),
        generatedBy: { userId: me.id, displayName: me.displayName },
        members: members.map((m) => ({ userId: m.userId, displayName: m.displayName })),
        drivers,
        sessions,
        _instructions: {
          predictions: 'One row per (userId, sessionId). picks count + positions must match the session\'s picksRequired. driverCode must be one of drivers above.',
          preseason: 'Optional. picks: one row per (userId, category) using driverCode or constructorId. standings: per-user driver+constructor projected ordering.',
          conflicts: 'When userId+sessionId already has an IN-APP pick, the row is rejected unless overwrite=true. Previously-imported rows are silently replaced.'
        },
        overwrite: false,
        predictions: [],
        preseason: { picks: [], standings: [] }
      }
    }
  )

  // ---- POST apply / dryRun -----------------------------------------------
  app.post<{ Params: { leagueId: string }; Querystring: { dryRun?: string }; Body: unknown }>(
    '/api/leagues/:leagueId/imports',
    { bodyLimit: MAX_BODY_BYTES },
    async (req) => {
      const { leagueId } = req.params
      await requireLeagueOwner(req, leagueId)
      const me = getCurrentUser(req)

      const dryRun = req.query.dryRun === '1' || req.query.dryRun === 'true'

      const parsed = ImportBody.safeParse(req.body)
      if (!parsed.success) {
        const summary = parsed.error.issues.slice(0, 5)
          .map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`).join('; ')
        throw new ApiError('VALIDATION', `Body failed schema validation. ${summary}`)
      }
      const body = parsed.data
      if (body.league.id !== leagueId) {
        throw new ApiError('BAD_REQUEST', 'league.id in body must match URL :leagueId')
      }

      const season = await seasonsRepo.getByYear(body.seasonYear)
      if (!season) throw new ApiError('NOT_FOUND', `Season ${body.seasonYear} not bootstrapped`)

      const members = await leagueMembers.listByLeague(leagueId)
      const memberIds = new Set(members.map((m) => m.userId))
      const memberById = new Map(members.map((m) => [m.userId, m.displayName]))

      // Build the season's session metadata for type + label lookup.
      const events = await eventsRepo.listForSeason(body.seasonYear)
      const sessionMetaById = new Map<number, { type: SessionType; eventName: string; round: number }>()
      for (const ev of events) {
        const ss = await sessionsRepo.listForEvent(ev.id)
        for (const s of ss) sessionMetaById.set(s.id, { type: s.type, eventName: ev.name, round: ev.round })
      }
      const validDrivers = new Set((await driversRepo.listAll()).map((d) => d.code))

      // ---- Plan predictions ----
      const plan: PredictionPlanItem[] = []
      const skipped: SkipItem[] = []
      const resultsCache = new Map<number, SessionResultRow[]>()

      for (const p of body.predictions) {
        if (!memberIds.has(p.userId)) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: 'not a league member' })
          continue
        }
        const meta = sessionMetaById.get(p.sessionId)
        if (!meta) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `session not in season ${body.seasonYear}` })
          continue
        }
        const required = picksRequiredFor(meta.type)
        if (!required) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `session ${meta.type} is not scorable` })
          continue
        }
        if (p.picks.length !== required) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `expected ${required} picks, got ${p.picks.length}` })
          continue
        }
        const positions = new Set(p.picks.map((pp) => pp.position))
        if (positions.size !== p.picks.length) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: 'duplicate position' })
          continue
        }
        const expected = new Set(Array.from({ length: required }, (_, i) => i + 1))
        if (![...positions].every((x) => expected.has(x))) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `positions must be 1..${required}` })
          continue
        }
        const unknownDrv = p.picks.find((pp) => !validDrivers.has(pp.driverCode))
        if (unknownDrv) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `unknown driver ${unknownDrv.driverCode}` })
          continue
        }

        // Determine conflict state — existing in-app picks need the
        // overwrite flag; existing import rows can be replaced silently.
        let conflictsWith: 'app' | 'import' | null = null
        const existing = await predictionsRepo.getByUserAndSession(p.userId, p.sessionId)
        if (existing) {
          const db = getDb()
          const [src] = await db.select({ source: prediction.source })
            .from(prediction).where(eq(prediction.id, existing.id)).limit(1)
          conflictsWith = (src?.source === 'import') ? 'import' : 'app'
        }

        // Compute score preview against current results (if available).
        let previewPoints: number | null = null
        let results = resultsCache.get(p.sessionId)
        if (!results) {
          results = await resultsRepo.listForSession(p.sessionId)
          resultsCache.set(p.sessionId, results)
        }
        if (results.length >= required) {
          const bd = scoreSession(meta.type, p.picks, finishersFor(results))
          previewPoints = totalOf(bd)
        }

        plan.push({
          userId: p.userId,
          sessionId: p.sessionId,
          sessionType: meta.type,
          eventName: meta.eventName,
          round: meta.round,
          picks: p.picks,
          conflictsWith,
          previewPoints
        })
      }

      // ---- Plan preseason picks ----
      const preseasonPickPlan: { userId: string; category: string; driverCode: string | null; constructorId: string | null }[] = []
      for (const pp of body.preseason?.picks ?? []) {
        if (!memberIds.has(pp.userId)) {
          skipped.push({ kind: 'preseason_pick', userId: pp.userId, category: pp.category, reason: 'not a league member' }); continue
        }
        if (!pp.driverCode && !pp.constructorId) {
          skipped.push({ kind: 'preseason_pick', userId: pp.userId, category: pp.category, reason: 'either driverCode or constructorId required' }); continue
        }
        if (pp.driverCode && !validDrivers.has(pp.driverCode)) {
          skipped.push({ kind: 'preseason_pick', userId: pp.userId, category: pp.category, reason: `unknown driver ${pp.driverCode}` }); continue
        }
        preseasonPickPlan.push({
          userId: pp.userId, category: pp.category,
          driverCode: pp.driverCode ?? null, constructorId: pp.constructorId ?? null
        })
      }

      // ---- Plan preseason standings ----
      const standingsPlan: { userId: string; drivers?: string[]; constructors?: string[] }[] = []
      for (const st of body.preseason?.standings ?? []) {
        if (!memberIds.has(st.userId)) {
          skipped.push({ kind: 'preseason_standings', userId: st.userId, reason: 'not a league member' }); continue
        }
        if (st.drivers && st.drivers.length > 0) {
          const unknown = st.drivers.find((c) => !validDrivers.has(c))
          if (unknown) {
            skipped.push({ kind: 'preseason_standings', userId: st.userId, reason: `unknown driver ${unknown}` }); continue
          }
        }
        standingsPlan.push({ userId: st.userId, drivers: st.drivers, constructors: st.constructors })
      }

      // ---- Build the response shell ----
      const overwriteList = plan.filter((x) => x.conflictsWith === 'app')
      const applyList = plan.filter((x) => x.conflictsWith !== 'app')

      // Per-member score preview: sum previewPoints from rows that would
      // actually be written (applyList in default mode; applyList + overwrite
      // when allowed). For the preview we always include both so the owner
      // sees the picture the toggle would deliver.
      const scorePreview = new Map<string, number>()
      for (const it of [...applyList, ...overwriteList]) {
        if (it.previewPoints == null) continue
        scorePreview.set(it.userId, (scorePreview.get(it.userId) ?? 0) + it.previewPoints)
      }

      const previewResponse = {
        dryRun: true as const,
        season: { year: body.seasonYear, name: `${body.seasonYear}` },
        members: members.map((m) => ({ userId: m.userId, displayName: m.displayName })),
        applied: {
          predictions: applyList.length,
          preseasonPicks: preseasonPickPlan.length,
          preseasonStandings: standingsPlan.length
        },
        overwrites: overwriteList.map((x) => ({
          userId: x.userId,
          displayName: memberById.get(x.userId) ?? x.userId,
          sessionId: x.sessionId,
          eventName: x.eventName,
          round: x.round,
          sessionType: x.sessionType,
          previewPoints: x.previewPoints
        })),
        plan: plan.map((x) => ({
          userId: x.userId,
          displayName: memberById.get(x.userId) ?? x.userId,
          sessionId: x.sessionId,
          eventName: x.eventName,
          round: x.round,
          sessionType: x.sessionType,
          picks: x.picks,
          conflictsWith: x.conflictsWith,
          previewPoints: x.previewPoints
        })),
        skipped,
        scorePreview: [...scorePreview.entries()].map(([userId, addedPoints]) => ({
          userId,
          displayName: memberById.get(userId) ?? userId,
          addedPoints
        })).sort((a, b) => b.addedPoints - a.addedPoints)
      }

      if (dryRun) return previewResponse

      // ---- Real apply ----
      if (overwriteList.length > 0 && !body.overwrite) {
        throw new ApiError('CONFLICT',
          `Upload would overwrite ${overwriteList.length} existing in-app pick(s). Re-submit with overwrite=true to confirm.`)
      }

      let appliedPredictions = 0
      let appliedPreseasonPicks = 0
      let appliedPreseasonStandings = 0
      const touchedSessions = new Set<number>()
      let touchedPreseason = false

      for (const it of plan) {
        if (it.conflictsWith === 'app' && !body.overwrite) continue
        await predictionsRepo.upsertPredictionWithPicks(
          it.userId, it.sessionId, it.picks,
          { source: 'import', importedBy: me.id }
        )
        touchedSessions.add(it.sessionId)
        appliedPredictions++
      }
      for (const pp of preseasonPickPlan) {
        await preseasonPicksRepo.upsertPick(pp.userId, body.seasonYear, pp.category as any, {
          driverCode: pp.driverCode, constructorId: pp.constructorId
        })
        touchedPreseason = true
        appliedPreseasonPicks++
      }
      for (const st of standingsPlan) {
        if (st.drivers && st.drivers.length > 0) {
          await preseasonStandings.replaceDriverPicks(st.userId, body.seasonYear,
            st.drivers.map((code, i) => ({ position: i + 1, entityId: code })))
          touchedPreseason = true
          appliedPreseasonStandings++
        }
        if (st.constructors && st.constructors.length > 0) {
          await preseasonStandings.replaceConstructorPicks(st.userId, body.seasonYear,
            st.constructors.map((id, i) => ({ position: i + 1, entityId: id })))
          touchedPreseason = true
        }
      }

      const db = getDb()
      const [auditRow] = await db.insert(predictionImport).values({
        leagueId,
        seasonYear: body.seasonYear,
        uploadedBy: me.id,
        schemaVersion: SCHEMA_VERSION,
        appliedCount: appliedPredictions + appliedPreseasonPicks + appliedPreseasonStandings,
        skippedCount: skipped.length
      }).returning()

      for (const sid of touchedSessions) {
        try { await rescoreSession(sid) } catch (err) { console.error('Rescore failed', { sid, err }) }
      }
      if (touchedPreseason) {
        try { await rescorePreseasonForSeason(body.seasonYear) } catch (err) {
          console.error('Preseason rescore failed', { year: body.seasonYear, err })
        }
      }

      return {
        dryRun: false as const,
        importId: auditRow!.id,
        applied: {
          predictions: appliedPredictions,
          preseasonPicks: appliedPreseasonPicks,
          preseasonStandings: appliedPreseasonStandings
        },
        overwriteCount: overwriteList.length,
        skipped,
        rescored: {
          sessions: touchedSessions.size,
          preseasonYears: touchedPreseason ? [body.seasonYear] : []
        }
      }
    }
  )

  // ---- GET audit list ----------------------------------------------------
  app.get<{ Params: { leagueId: string } }>(
    '/api/leagues/:leagueId/imports',
    async (req) => {
      const { leagueId } = req.params
      await requireLeagueMember(req, leagueId)
      const db = getDb()
      const rows = await db.select({
        id: predictionImport.id,
        uploadedAt: predictionImport.uploadedAt,
        uploadedById: predictionImport.uploadedBy,
        seasonYear: predictionImport.seasonYear,
        appliedCount: predictionImport.appliedCount,
        skippedCount: predictionImport.skippedCount,
        schemaVersion: predictionImport.schemaVersion
      })
        .from(predictionImport)
        .where(eq(predictionImport.leagueId, leagueId))
        .orderBy(predictionImport.uploadedAt)
      if (rows.length === 0) return []
      const uploaderIds = [...new Set(rows.map((r) => r.uploadedById))]
      const uploaders = await db.select({ id: userTable.id, displayName: userTable.displayName })
        .from(userTable).where(inArray(userTable.id, uploaderIds))
      const nameById = new Map(uploaders.map((u) => [u.id, u.displayName]))
      return rows.map((r) => ({
        id: r.id,
        uploadedAt: r.uploadedAt,
        uploadedBy: nameById.get(r.uploadedById) ?? '(unknown)',
        seasonYear: r.seasonYear,
        appliedCount: r.appliedCount,
        skippedCount: r.skippedCount,
        schemaVersion: r.schemaVersion
      })).reverse()
    }
  )
}

function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'league'
}
