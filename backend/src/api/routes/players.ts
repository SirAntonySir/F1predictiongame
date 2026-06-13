/// Composite player profile endpoint:
///   GET /api/leagues/:leagueId/players/:userId?season=YYYY
///
/// Returns everything the player screen needs in one round-trip: standing,
/// recent form, insight cards, preseason picks, and the locked-pick log.
///
/// Locked-pick filter: only sessions whose scheduledStart is in the past are
/// included. The caller can't see other members' upcoming/draft picks; only
/// already-public ones.
import { eq, and, desc, sql, inArray, lt } from 'drizzle-orm'
import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { getCurrentUser, registerAuthHook, requireLeagueMember } from '../auth-context.js'
import { ApiError } from '../errors.js'
import { getDb } from '../../db/client.js'
import {
  prediction, predictionPick, session, event, sessionResult,
  leagueMember, user as userTable, preseasonPick, preseasonPickStandingsDriver,
  preseasonPickStandingsConstructor, preseasonProjectionSnapshot, score
} from '../../db/schema.js'
import * as scoresRepo from '../../repo/scores.js'
import * as seasonsRepo from '../../repo/seasons.js'

const QueryZ = z.object({ season: z.string().optional() })

type Glyph = 'exact' | 'wrongPos' | 'miss' | 'teamBonus'

type BreakdownPerPosition = { position: number; exact: boolean; wrongPos: boolean; points: number; driverCode?: string }
type StoredBreakdown = {
  perPosition: BreakdownPerPosition[]
  teamBonus: { applied: boolean; points: number }
}

function glyphsFor(bd: StoredBreakdown): Glyph[] {
  const out: Glyph[] = bd.perPosition.map((p) =>
    p.exact ? 'exact' : (p.wrongPos ? 'wrongPos' : 'miss')
  )
  if (bd.teamBonus.applied) out.push('teamBonus')
  return out
}

export async function registerPlayerRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.get<{ Params: { leagueId: string; userId: string }; Querystring: { season?: string } }>(
    '/api/leagues/:leagueId/players/:userId',
    async (req) => {
      const { leagueId, userId: targetId } = req.params
      await requireLeagueMember(req, leagueId)
      const caller = getCurrentUser(req)

      // Target must also be in the league (otherwise 404 — don't leak
      // membership info to outsiders by distinguishing from 403).
      const db = getDb()
      const [membership] = await db.select({
        userId: leagueMember.userId,
        displayName: userTable.displayName,
        joinedAt: leagueMember.joinedAt
      })
        .from(leagueMember)
        .innerJoin(userTable, eq(userTable.id, leagueMember.userId))
        .where(and(eq(leagueMember.leagueId, leagueId), eq(leagueMember.userId, targetId)))
        .limit(1)
      if (!membership) throw new ApiError('NOT_FOUND', 'Player not in this league')

      // Resolve season.
      const parsed = QueryZ.safeParse(req.query)
      const seasonYearRaw = parsed.success ? parsed.data.season : undefined
      let seasonYear: number
      if (seasonYearRaw && /^\d{4}$/.test(seasonYearRaw)) {
        seasonYear = Number(seasonYearRaw)
      } else {
        const cur = await seasonsRepo.getCurrent()
        if (!cur) throw new ApiError('NOT_FOUND', 'No current season')
        seasonYear = cur.year
      }

      // ---- League standing ----
      const lb = await scoresRepo.leagueLeaderboard(leagueId, seasonYear)
      // leagueLeaderboard returns sorted desc by pointsTotal already.
      const targetIdx = lb.findIndex((r) => r.userId === targetId)
      const targetLb = targetIdx === -1 ? null : lb[targetIdx]
      const standing = {
        leagueRank: targetIdx === -1 ? null : targetIdx + 1,
        leagueSize: lb.length,
        pointsTotal: targetLb?.pointsTotal ?? 0,
        inSeasonPoints: targetLb?.inSeasonPoints ?? 0,
        preseasonPoints: targetLb?.preseasonPoints ?? 0,
        sessionsScored: targetLb?.sessionsScored ?? 0
      }

      // ---- Scored sessions (desc by start) ----
      const scored = await scoresRepo.listForUser(targetId, seasonYear)

      // Recent form = last 5
      const recentForm = scored.slice(0, 5).map((s) => ({
        sessionId: s.sessionId,
        round: s.eventRound,
        eventName: s.eventName,
        sessionType: s.sessionType,
        points: s.pointsTotal,
        glyphs: glyphsFor(s.breakdown as StoredBreakdown)
      }))

      // ---- Insights derived from scored sessions ----
      let bestSingle: { sessionId: number; eventName: string; sessionType: string; points: number } | null = null
      let exactSlots = 0, totalSlots = 0
      let teamBonusEligible = 0, teamBonusApplied = 0
      for (const s of scored) {
        const bd = s.breakdown as StoredBreakdown
        if (!bestSingle || s.pointsTotal > bestSingle.points) {
          bestSingle = {
            sessionId: s.sessionId,
            eventName: s.eventName,
            sessionType: s.sessionType,
            points: s.pointsTotal
          }
        }
        for (const p of bd.perPosition) {
          totalSlots++
          if (p.exact) exactSlots++
        }
        // P1 was picked → team-bonus eligible (a pick of position 1 exists).
        if (bd.perPosition.some((p) => p.position === 1)) {
          teamBonusEligible++
          if (bd.teamBonus.applied) teamBonusApplied++
        }
      }

      // Most-picked P1 across all in-season races so far.
      const p1Rows = await db
        .select({
          driverCode: predictionPick.driverCode,
          count: sql<number>`count(*)::int`.as('count')
        })
        .from(predictionPick)
        .innerJoin(prediction, eq(prediction.id, predictionPick.predictionId))
        .innerJoin(session, eq(session.id, prediction.sessionId))
        .innerJoin(event, eq(event.id, session.eventId))
        .where(and(
          eq(prediction.userId, targetId),
          eq(event.seasonYear, seasonYear),
          eq(predictionPick.position, 1)
        ))
        .groupBy(predictionPick.driverCode)
        .orderBy(desc(sql`count(*)`))
      const mostPickedP1 = p1Rows.length === 0
        ? null
        : { driverCode: p1Rows[0]!.driverCode, count: Number(p1Rows[0]!.count) }

      const insights = {
        mostPickedP1,
        bestSingleSession: bestSingle,
        exactHitRate: totalSlots === 0 ? null : exactSlots / totalSlots,
        teamBonusRate: teamBonusEligible === 0 ? null : teamBonusApplied / teamBonusEligible,
        sessionsScored: scored.length,
        totalSlots,
        exactSlots
      }

      // ---- Preseason ----
      const pPicks = await db.select().from(preseasonPick)
        .where(and(eq(preseasonPick.userId, targetId), eq(preseasonPick.seasonYear, seasonYear)))
      const pDriverStandings = await db.select({
        position: preseasonPickStandingsDriver.position,
        driverCode: preseasonPickStandingsDriver.driverCode
      })
        .from(preseasonPickStandingsDriver)
        .where(and(eq(preseasonPickStandingsDriver.userId, targetId),
          eq(preseasonPickStandingsDriver.seasonYear, seasonYear)))
        .orderBy(preseasonPickStandingsDriver.position)
      const pConstructorStandings = await db.select({
        position: preseasonPickStandingsConstructor.position,
        constructorId: preseasonPickStandingsConstructor.constructorId
      })
        .from(preseasonPickStandingsConstructor)
        .where(and(eq(preseasonPickStandingsConstructor.userId, targetId),
          eq(preseasonPickStandingsConstructor.seasonYear, seasonYear)))
        .orderBy(preseasonPickStandingsConstructor.position)
      const [latestProj] = await db.select({
        projectedPoints: preseasonProjectionSnapshot.projectedPoints,
        afterSessionId: preseasonProjectionSnapshot.afterSessionId
      })
        .from(preseasonProjectionSnapshot)
        .where(and(eq(preseasonProjectionSnapshot.userId, targetId),
          eq(preseasonProjectionSnapshot.seasonYear, seasonYear)))
        .orderBy(desc(preseasonProjectionSnapshot.computedAt))
        .limit(1)
      const preseason = {
        picks: pPicks.map((p) => ({
          category: p.category,
          driverCode: p.driverCode,
          constructorId: p.constructorId
        })),
        driverStandings: pDriverStandings,
        constructorStandings: pConstructorStandings,
        projectedTotal: latestProj?.projectedPoints ?? null
      }

      // ---- Locked-pick log ----
      // Sessions whose start is in the past + the user has a prediction for.
      const now = new Date()
      const lockedSessions = await db.select({
        predictionId: prediction.id,
        sessionId: session.id,
        sessionType: session.type,
        round: event.round,
        eventName: event.name,
        scheduledStart: session.scheduledStart,
        source: prediction.source,
        importedAt: prediction.importedAt
      })
        .from(prediction)
        .innerJoin(session, eq(session.id, prediction.sessionId))
        .innerJoin(event, eq(event.id, session.eventId))
        .where(and(
          eq(prediction.userId, targetId),
          eq(event.seasonYear, seasonYear),
          lt(session.scheduledStart, now)
        ))
        .orderBy(desc(session.scheduledStart))

      let pickLog: any[] = []
      if (lockedSessions.length > 0) {
        const predIds = lockedSessions.map((l) => l.predictionId)
        const sessionIds = lockedSessions.map((l) => l.sessionId)
        const picks = await db.select({
          predictionId: predictionPick.predictionId,
          position: predictionPick.position,
          driverCode: predictionPick.driverCode
        })
          .from(predictionPick)
          .where(inArray(predictionPick.predictionId, predIds))
          .orderBy(predictionPick.position)
        const picksByPred = new Map<string, { position: number; driverCode: string }[]>()
        for (const p of picks) {
          (picksByPred.get(p.predictionId) ?? picksByPred.set(p.predictionId, []).get(p.predictionId)!)
            .push({ position: p.position, driverCode: p.driverCode })
        }
        const scoreRows = await db.select({
          sessionId: score.sessionId,
          pointsTotal: score.pointsTotal,
          breakdown: score.breakdown
        })
          .from(score)
          .where(and(
            eq(score.userId, targetId),
            inArray(score.sessionId, sessionIds),
            eq(score.kind, 'session')
          ))
        const scoreBySession = new Map<number, { points: number; breakdown: StoredBreakdown }>()
        for (const r of scoreRows) {
          scoreBySession.set(r.sessionId as number, {
            points: r.pointsTotal,
            breakdown: r.breakdown as StoredBreakdown
          })
        }
        // Actual results (top-N) for visual diffing.
        const resultRows = await db.select({
          sessionId: sessionResult.sessionId,
          position: sessionResult.position,
          driverCode: sessionResult.driverCode,
          constructorId: sessionResult.constructorId
        })
          .from(sessionResult)
          .where(inArray(sessionResult.sessionId, sessionIds))
          .orderBy(sessionResult.position)
        const resultsBySession = new Map<number, { position: number; driverCode: string; constructorId: string }[]>()
        for (const r of resultRows) {
          (resultsBySession.get(r.sessionId) ??
            resultsBySession.set(r.sessionId, []).get(r.sessionId)!).push(r)
        }

        pickLog = lockedSessions.map((l) => ({
          sessionId: l.sessionId,
          round: l.round,
          eventName: l.eventName,
          sessionType: l.sessionType,
          scheduledStart: l.scheduledStart,
          source: l.source,
          importedAt: l.importedAt,
          picks: picksByPred.get(l.predictionId) ?? [],
          // Top-N of results so the UI can compare side-by-side; full result
          // already available via /api/sessions/:id/results if the client
          // wants more.
          topResults: (resultsBySession.get(l.sessionId) ?? []).slice(0, 5),
          score: scoreBySession.get(l.sessionId) ?? null
        }))
      }

      return {
        player: {
          userId: targetId,
          displayName: membership.displayName,
          joinedAt: membership.joinedAt,
          isSelf: targetId === caller.id
        },
        season: { year: seasonYear },
        standing,
        recentForm,
        insights,
        preseason,
        pickLog
      }
    }
  )
}
