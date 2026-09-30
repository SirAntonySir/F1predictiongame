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
import xlsxPkg from 'xlsx'
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
import * as constructorsRepo from '../../repo/constructors.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as predictionPicksRepo from '../../repo/predictionPicks.js'
import * as resultsRepo from '../../repo/results.js'
import * as preseasonPicksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandings from '../../repo/preseasonStandings.js'
import { picksRequiredFor, scoreSession } from '../../scoring/index.js'
import { rescoreSession } from '../../scoring/rescorer.js'
import { rescorePreseasonForSeason } from '../../preseason/rescorer.js'
import { JOKERS_PER_SEASON } from '../../jokers/applier.js'
import { parseWorkbook } from '../../scripts/tippspiel/parser.js'
import { SESSION_TYPE_BY_KIND } from '../../scripts/tippspiel/types.js'
import type { ParsedSeason } from '../../scripts/tippspiel/types.js'
import { mapEventName } from '../../scripts/tippspiel/mappings.js'
import type { SessionType, SessionResultRow } from '../../domain/types.js'
import type { Finisher } from '../../scoring/types.js'

const XLSX = xlsxPkg as typeof xlsxPkg & { read: (data: Buffer, opts: { type: 'buffer' }) => xlsxPkg.WorkBook }

const SCHEMA_VERSION = 1
const MAX_BODY_BYTES = 256 * 1024
const MAX_XLSX_BYTES = 2 * 1024 * 1024
const MAX_PREDICTIONS = 5000
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'

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
    })).min(1),
    /// True = this row consumed one of the user's 3 season jokers (missed
    /// race auto-copy or late hand-in). Race sessions only; budget-checked.
    joker: z.boolean().default(false)
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
  }).optional(),
  // Template round-trip: the downloaded schema file carries reference and
  // documentation keys — owners upload the filled file as-is, so these are
  // explicitly tolerated (and ignored) instead of tripping strict().
  generatedAt: z.unknown().optional(),
  generatedBy: z.unknown().optional(),
  members: z.unknown().optional(),
  drivers: z.unknown().optional(),
  constructors: z.unknown().optional(),
  preseasonCategories: z.unknown().optional(),
  sessions: z.unknown().optional(),
  _instructions: z.unknown().optional(),
  _example: z.unknown().optional()
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
  joker: boolean
  /// 'app' = existing in-app pick will be replaced.
  /// 'import' = previous import/joker row will be replaced (no warning needed).
  /// null = brand-new row.
  conflictsWith: 'app' | 'import' | null
  /// Points the picks WOULD score, given the session's current results. Null
  /// if the session has no results (race not run yet, etc).
  previewPoints: number | null
}
type SkipItem = { kind: string; userId?: string; sessionId?: number; category?: string; reason: string }
type WarnItem = { userId: string; displayName: string; sessionId: number; eventName: string; round: number; reason: string }

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

  // Binary body support for the xlsx endpoint. Encapsulated to this plugin —
  // JSON routes still require application/json.
  for (const type of ['application/octet-stream', XLSX_MIME]) {
    app.addContentTypeParser(type, { parseAs: 'buffer' }, (_req, body, done) => done(null, body))
  }

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
      const constructors = (await constructorsRepo.listAll())
        .map((c) => ({ id: c.id, name: c.name }))
        .sort((a, b) => a.id.localeCompare(b.id))
      const me = getCurrentUser(req)

      // Concrete example rows beat prose — real ids from THIS league/season so
      // a human or AI can pattern-match instead of guessing.
      const exampleSession = sessions.find((s) => s.type === 'race') ?? sessions[0]
      const exampleMember = members[0]
      const example = exampleSession && exampleMember ? {
        _note: 'Example rows only — replace and delete. Shapes: full set, partial hand-in, joker.',
        predictions: [
          {
            userId: exampleMember.userId,
            sessionId: exampleSession.sessionId,
            picks: Array.from({ length: exampleSession.picksRequired }, (_, i) => ({
              position: i + 1, driverCode: drivers[i % drivers.length] ?? 'VER'
            }))
          },
          {
            userId: exampleMember.userId,
            sessionId: exampleSession.sessionId,
            picks: [{ position: 1, driverCode: drivers[0] ?? 'VER' }],
            _note: 'partial hand-in: only the filled positions score'
          },
          {
            userId: exampleMember.userId,
            sessionId: exampleSession.sessionId,
            picks: [{ position: 1, driverCode: drivers[0] ?? 'VER' }],
            joker: true,
            _note: `joker row (race only, max ${JOKERS_PER_SEASON}/season)`
          }
        ]
      } : undefined

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
        constructors,
        preseasonCategories: ['surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'],
        sessions,
        _instructions: {
          predictions: 'One row per (userId, sessionId). Up to picksRequired picks, positions within 1..picksRequired (partial hand-ins allowed — filled positions score normally). driverCode must be one of drivers above.',
          jokers: `Set "joker": true on a race row that consumed one of the ${JOKERS_PER_SEASON} season jokers (missed race / late hand-in). Budget is validated; excess joker rows are skipped. Rows identical to the previous race without the flag get a warning in the preview.`,
          preseason: 'Optional. picks: one row per (userId, category) from preseasonCategories, using driverCode and/or constructorId (ids from constructors above). standings: per-user projected ordering — drivers as an ordered driverCode array, constructors as an ordered constructor-id array.',
          conflicts: 'When userId+sessionId already has an IN-APP pick, the row is rejected unless overwrite=true. Previously imported or joker rows are replaced silently; rows identical to what is already stored are skipped as unchanged.',
          points: 'Never submit points — every touched session is rescored by the engine from official results.',
          excel: 'Alternative to this file: POST the maintained Tippspiel xlsx (binary) to /imports/excel?season=YYYY — same preview/apply pipeline.'
        },
        _example: example,
        overwrite: false,
        predictions: [],
        preseason: { picks: [], standings: [] }
      }
    }
  )

  // ---- Shared plan/apply pipeline (JSON + Excel endpoints) -----------------
  async function runImport(
    leagueId: string,
    me: { id: string },
    body: ImportBodyT,
    dryRun: boolean
  ) {
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
      // Race sessions by round, for joker bookkeeping + the previous-race heuristic.
      const raceSessionByRound = new Map<number, number>()
      for (const [sid, m] of sessionMetaById) {
        if (m.type === 'race') raceSessionByRound.set(m.round, sid)
      }
      const raceRoundsAsc = [...raceSessionByRound.keys()].sort((a, b) => a - b)
      const validDrivers = new Set((await driversRepo.listAll()).map((d) => d.code))

      // ---- Plan predictions ----
      const plan: PredictionPlanItem[] = []
      const skipped: SkipItem[] = []
      const warnings: WarnItem[] = []
      const resultsCache = new Map<number, SessionResultRow[]>()

      // Existing predictions per session (source + picks), fetched lazily one
      // session at a time. Serves conflict detection, the unchanged-row check
      // and the missed-race heuristic.
      const existingCache = new Map<number, Map<string, { source: string; picks: Pick[] }>>()
      async function existingAt(sessionId: number): Promise<Map<string, { source: string; picks: Pick[] }>> {
        let m = existingCache.get(sessionId)
        if (!m) {
          m = new Map(
            (await predictionsRepo.listForSessionWithPicks(sessionId))
              .map((r) => [r.userId, { source: r.source, picks: r.picks }])
          )
          existingCache.set(sessionId, m)
        }
        return m
      }
      const samePicks = (a: Pick[], b: Pick[]) =>
        a.length > 0 && a.length === b.length &&
        [...a].sort((x, y) => x.position - y.position).every((p, i) => {
          const q = [...b].sort((x, y) => x.position - y.position)[i]!
          return p.position === q.position && p.driverCode === q.driverCode
        })

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
        // Partial sets are legal (late/partial hand-ins): 1..required picks,
        // each at a distinct position within 1..required. The engine scores
        // filled positions; empty ones simply can't score.
        if (p.picks.length > required) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `too many picks: max ${required}, got ${p.picks.length}` })
          continue
        }
        const positions = new Set(p.picks.map((pp) => pp.position))
        if (positions.size !== p.picks.length) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: 'duplicate position' })
          continue
        }
        const expected = new Set(Array.from({ length: required }, (_, i) => i + 1))
        if (![...positions].every((x) => expected.has(x))) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `positions must be within 1..${required}` })
          continue
        }
        const unknownDrv = p.picks.find((pp) => !validDrivers.has(pp.driverCode))
        if (unknownDrv) {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: `unknown driver ${unknownDrv.driverCode}` })
          continue
        }
        if (p.joker && meta.type !== 'race') {
          skipped.push({ kind: 'prediction', userId: p.userId, sessionId: p.sessionId, reason: 'joker only valid on race sessions' })
          continue
        }

        // Determine conflict state — existing in-app picks need the
        // overwrite flag; import/joker rows (machine-written) are replaced
        // silently.
        const existing = (await existingAt(p.sessionId)).get(p.userId) ?? null
        const conflictsWith: 'app' | 'import' | null =
          existing === null ? null : (existing.source === 'app' ? 'app' : 'import')

        // Unchanged rows are left alone entirely. This makes full-sheet
        // re-uploads no-ops AND preserves joker labels the Excel can't know
        // about (the sheet carries the copied picks but no joker marker).
        // The one identical-picks case that still applies: joker:true over a
        // row that isn't labelled joker yet — that's a deliberate label fix.
        if (existing && samePicks(p.picks, existing.picks) && !(p.joker && existing.source !== 'joker')) {
          skipped.push({
            kind: 'prediction', userId: p.userId, sessionId: p.sessionId,
            reason: existing.source === 'joker'
              ? 'unchanged — existing joker row kept'
              : 'unchanged — identical picks already present'
          })
          continue
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
          joker: p.joker,
          conflictsWith,
          previewPoints
        })
      }

      // ---- Joker budget (3 per user per season) ----
      // Final joker set per user = existing joker rows NOT replaced by this
      // upload + uploaded rows flagged joker:true. Excess joker rows (later
      // rounds first kept out) are moved to skipped.
      const jokerBudgetRelevant = plan.some((x) => x.joker) || plan.some((x) => x.sessionType === 'race')
      if (jokerBudgetRelevant) {
        const db = getDb()
        const existingJokerRows = await db
          .select({ userId: prediction.userId, sessionId: prediction.sessionId })
          .from(prediction)
          .where(eq(prediction.source, 'joker'))
        const seasonSessionIds = new Set(sessionMetaById.keys())
        const existingJokersByUser = new Map<string, Set<number>>()
        for (const r of existingJokerRows) {
          if (!seasonSessionIds.has(r.sessionId)) continue
          if (!existingJokersByUser.has(r.userId)) existingJokersByUser.set(r.userId, new Set())
          existingJokersByUser.get(r.userId)!.add(r.sessionId)
        }
        const plannedByUser = new Map<string, PredictionPlanItem[]>()
        for (const x of plan) {
          if (!plannedByUser.has(x.userId)) plannedByUser.set(x.userId, [])
          plannedByUser.get(x.userId)!.push(x)
        }
        for (const [userId, items] of plannedByUser) {
          const replacedSessions = new Set(items.map((x) => x.sessionId))
          const keptExisting = [...(existingJokersByUser.get(userId) ?? [])]
            .filter((sid) => !replacedSessions.has(sid)).length
          const plannedJokers = items.filter((x) => x.joker).sort((a, b) => a.round - b.round)
          const budget = JOKERS_PER_SEASON - keptExisting
          for (let i = budget; i < plannedJokers.length; i++) {
            const x = plannedJokers[i]!
            plan.splice(plan.indexOf(x), 1)
            skipped.push({
              kind: 'prediction', userId, sessionId: x.sessionId,
              reason: `joker budget exceeded: only ${JOKERS_PER_SEASON} per season (${keptExisting} already used outside this upload)`
            })
          }
        }
      }

      // ---- Missed-race heuristic ----
      // A non-joker race row whose picks are identical to the same user's
      // previous-race picks usually means the race was missed and the picks
      // were copied — probably should be joker: true. Warn, don't block.
      const plannedPicksByUserSession = new Map<string, Pick[]>()
      for (const x of plan) plannedPicksByUserSession.set(`${x.userId}:${x.sessionId}`, x.picks)
      async function picksAt(userId: string, sessionId: number): Promise<Pick[] | null> {
        const uploaded = plannedPicksByUserSession.get(`${userId}:${sessionId}`)
        if (uploaded) return uploaded
        return (await existingAt(sessionId)).get(userId)?.picks ?? null
      }
      for (const x of plan) {
        if (x.joker || x.sessionType !== 'race') continue
        const prevRound = raceRoundsAsc.filter((r) => r < x.round).pop()
        if (prevRound === undefined) continue
        const prevPicks = await picksAt(x.userId, raceSessionByRound.get(prevRound)!)
        if (prevPicks && samePicks(x.picks, prevPicks)) {
          warnings.push({
            userId: x.userId,
            displayName: memberById.get(x.userId) ?? x.userId,
            sessionId: x.sessionId,
            eventName: x.eventName,
            round: x.round,
            reason: `picks identical to the previous race (round ${prevRound}) — missed race? Consider marking this row "joker": true`
          })
        }
      }

      // ---- Plan preseason picks ----
      const validConstructors = new Set((await constructorsRepo.listAll()).map((c) => c.id))
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
        if (pp.constructorId && !validConstructors.has(pp.constructorId)) {
          skipped.push({ kind: 'preseason_pick', userId: pp.userId, category: pp.category, reason: `unknown constructor ${pp.constructorId}` }); continue
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
        if (st.constructors && st.constructors.length > 0) {
          const unknown = st.constructors.find((c) => !validConstructors.has(c))
          if (unknown) {
            skipped.push({ kind: 'preseason_standings', userId: st.userId, reason: `unknown constructor ${unknown}` }); continue
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
          joker: x.joker,
          conflictsWith: x.conflictsWith,
          previewPoints: x.previewPoints
        })),
        skipped,
        warnings,
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
          { source: it.joker ? 'joker' : 'import', importedBy: me.id }
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
        warnings,
        rescored: {
          sessions: touchedSessions.size,
          preseasonYears: touchedPreseason ? [body.seasonYear] : []
        }
      }
  }

  // ---- POST apply / dryRun (JSON) -----------------------------------------
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
      return runImport(leagueId, me, body, dryRun)
    }
  )

  // ---- POST Excel upload ---------------------------------------------------
  // Accepts the maintained Tippspiel xlsx as a raw binary body and runs it
  // through the same plan/apply pipeline as the JSON endpoint. The sheet has
  // no joker markers, so every row imports as joker:false — the missed-race
  // heuristic in the preview flags candidates for a follow-up JSON upload.
  app.post<{ Params: { leagueId: string }; Querystring: { season?: string; dryRun?: string; overwrite?: string }; Body: Buffer }>(
    '/api/leagues/:leagueId/imports/excel',
    { bodyLimit: MAX_XLSX_BYTES },
    async (req) => {
      const { leagueId } = req.params
      await requireLeagueOwner(req, leagueId)
      const me = getCurrentUser(req)
      const dryRun = req.query.dryRun === '1' || req.query.dryRun === 'true'
      const overwrite = req.query.overwrite === '1' || req.query.overwrite === 'true'

      const seasonYear = Number(req.query.season)
      if (!Number.isFinite(seasonYear)) {
        throw new ApiError('BAD_REQUEST', 'season query param required (year)')
      }
      if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
        throw new ApiError('BAD_REQUEST', 'request body must be the xlsx file (binary)')
      }

      let parsedSeason: ParsedSeason
      try {
        const wb = XLSX.read(req.body, { type: 'buffer' })
        parsedSeason = parseWorkbook(wb, seasonYear)
      } catch (e) {
        throw new ApiError('VALIDATION', `Could not parse workbook: ${e instanceof Error ? e.message : String(e)}`)
      }

      const league = await leaguesRepo.findById(leagueId)
      if (!league) throw new ApiError('NOT_FOUND', 'League not found')
      const { body, skippedUpfront } = await excelToImportBody(parsedSeason, leagueId, league.name, overwrite)
      const result = await runImport(leagueId, me, body, dryRun)
      // Surface players/events the Excel mentions but the league/DB doesn't know.
      result.skipped.push(...skippedUpfront)
      return result
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

/// Map a parsed Tippspiel workbook onto the JSON import body shape so the
/// Excel endpoint can reuse the exact same plan/apply pipeline. Players are
/// matched to league members by display name; players/events the DB doesn't
/// know are reported via [skippedUpfront] instead of failing the upload.
async function excelToImportBody(
  parsed: ParsedSeason,
  leagueId: string,
  leagueName: string,
  overwrite: boolean
): Promise<{ body: ImportBodyT; skippedUpfront: SkipItem[] }> {
  const skippedUpfront: SkipItem[] = []

  const members = await leagueMembers.listByLeague(leagueId)
  const memberIdByName = new Map(members.map((m) => [m.displayName, m.userId]))

  const events = await eventsRepo.listForSeason(parsed.seasonYear)
  const eventByName = new Map(events.map((e) => [e.name, e]))
  const sessionIdByEventAndType = new Map<string, number>()
  for (const ev of events) {
    for (const s of await sessionsRepo.listForEvent(ev.id)) {
      sessionIdByEventAndType.set(`${ev.id}:${s.type}`, s.id)
    }
  }

  type PreseasonPickRow = NonNullable<NonNullable<ImportBodyT['preseason']>['picks']>[number]
  type PreseasonStandingsRow = NonNullable<NonNullable<ImportBodyT['preseason']>['standings']>[number]
  const predictions: ImportBodyT['predictions'] = []
  const preseasonPicks: PreseasonPickRow[] = []
  const preseasonStandings: PreseasonStandingsRow[] = []

  for (const player of parsed.players) {
    const userId = memberIdByName.get(player.excelName)
    if (!userId) {
      skippedUpfront.push({ kind: 'excel_player', reason: `Excel player "${player.excelName}" is not a member of this league` })
      continue
    }

    for (const [excelEventName, picks] of Object.entries(player.racePicks)) {
      const hasAnyPicks = (['quali', 'sprintQuali', 'sprint', 'race'] as const).some((k) => picks[k].length > 0)
      const dbEventName = mapEventName(excelEventName)
      if (dbEventName === null) {
        if (hasAnyPicks) skippedUpfront.push({ kind: 'excel_event', userId, reason: `unknown event header "${excelEventName}"` })
        continue
      }
      const ev = eventByName.get(dbEventName)
      if (!ev) {
        if (hasAnyPicks) skippedUpfront.push({ kind: 'excel_event', userId, reason: `event "${dbEventName}" not in season ${parsed.seasonYear}` })
        continue
      }
      for (const kind of ['quali', 'sprintQuali', 'sprint', 'race'] as const) {
        const list = picks[kind]
        if (list.length === 0) continue
        const sessionId = sessionIdByEventAndType.get(`${ev.id}:${SESSION_TYPE_BY_KIND[kind]}`)
        if (sessionId === undefined) {
          skippedUpfront.push({ kind: 'excel_session', userId, reason: `no ${SESSION_TYPE_BY_KIND[kind]} session for "${dbEventName}"` })
          continue
        }
        predictions.push({ userId, sessionId, picks: list, joker: false })
      }
    }

    for (const [category, vals] of Object.entries(player.preseasonSingle)) {
      preseasonPicks.push({
        userId,
        category: category as PreseasonPickRow['category'],
        driverCode: vals.driverCode ?? undefined,
        constructorId: vals.constructorId ?? undefined
      })
    }
    if (player.preseasonStandings.drivers.length > 0 || player.preseasonStandings.constructors.length > 0) {
      preseasonStandings.push({
        userId,
        drivers: player.preseasonStandings.drivers.map((d) => d.driverCode),
        constructors: player.preseasonStandings.constructors.map((c) => c.constructorId)
      })
    }
  }

  return {
    body: {
      schemaVersion: SCHEMA_VERSION,
      league: { id: leagueId, name: leagueName },
      seasonYear: parsed.seasonYear,
      overwrite,
      predictions,
      preseason: { picks: preseasonPicks, standings: preseasonStandings }
    },
    skippedUpfront
  }
}
