import { and, desc, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { score, session, event, leagueMember, user } from '../db/schema.js'
import type { Score, ScoreBreakdown } from '../domain/types.js'

export type LeaderboardRow = {
  userId: string
  displayName: string
  pointsTotal: number
  sessionsScored: number
}

export type UserScoreRow = Score & {
  sessionType: string
  sessionScheduledStart: Date
  eventRound: number
  eventName: string
}

export async function upsertScore(
  userId: string,
  sessionId: number,
  pointsTotal: number,
  breakdown: ScoreBreakdown
): Promise<void> {
  const db = getDb()
  await db.insert(score)
    .values({ userId, sessionId, pointsTotal, breakdown })
    .onConflictDoUpdate({
      target: [score.userId, score.sessionId],
      set: { pointsTotal, breakdown, computedAt: sql`now()` }
    })
}

export async function listForUser(userId: string, seasonYear: number): Promise<UserScoreRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: score.userId,
      sessionId: score.sessionId,
      pointsTotal: score.pointsTotal,
      breakdown: score.breakdown,
      computedAt: score.computedAt,
      sessionType: session.type,
      sessionScheduledStart: session.scheduledStart,
      eventRound: event.round,
      eventName: event.name
    })
    .from(score)
    .innerJoin(session, eq(session.id, score.sessionId))
    .innerJoin(event, eq(event.id, session.eventId))
    .where(and(eq(score.userId, userId), eq(event.seasonYear, seasonYear)))
    .orderBy(desc(session.scheduledStart))

  return rows.map((r) => ({
    userId: r.userId,
    sessionId: r.sessionId,
    pointsTotal: r.pointsTotal,
    breakdown: r.breakdown as ScoreBreakdown,
    computedAt: r.computedAt,
    sessionType: r.sessionType,
    sessionScheduledStart: r.sessionScheduledStart,
    eventRound: r.eventRound,
    eventName: r.eventName
  }))
}

/**
 * Per-league leaderboard for a season. Every league member appears, even those with zero score.
 */
export async function leagueLeaderboard(leagueId: string, seasonYear: number): Promise<LeaderboardRow[]> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT
      lm.user_id::text AS "userId",
      u.display_name   AS "displayName",
      COALESCE(SUM(s.points_total), 0)::int AS "pointsTotal",
      COUNT(s.session_id)::int              AS "sessionsScored"
    FROM ${leagueMember} lm
    JOIN ${user} u ON u.id = lm.user_id
    LEFT JOIN (
      SELECT s.user_id, s.session_id, s.points_total
      FROM ${score} s
      JOIN ${session} ses ON ses.id = s.session_id
      JOIN ${event} ev ON ev.id = ses.event_id
      WHERE ev.season_year = ${seasonYear}
    ) s ON s.user_id = lm.user_id
    WHERE lm.league_id = ${leagueId}
    GROUP BY lm.user_id, u.display_name
    ORDER BY "pointsTotal" DESC, "displayName" ASC
  `)
  return (rows as unknown as { rows: LeaderboardRow[] }).rows
}

export type SessionLeaderboardRow = {
  sessionId: number
  sessionType: string
  eventRound: number
  eventName: string
  scheduledStart: Date
  members: { userId: string; displayName: string; pointsTotal: number; breakdown: ScoreBreakdown }[]
}

/**
 * Per-session breakdown for a league: every (member, session) row for the season, ordered chronologically.
 * Members with no score for a given session are omitted from that session's `members` array.
 */
export async function leagueSessionBreakdown(leagueId: string, seasonYear: number): Promise<SessionLeaderboardRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      sessionId: score.sessionId,
      sessionType: session.type,
      eventRound: event.round,
      eventName: event.name,
      scheduledStart: session.scheduledStart,
      userId: score.userId,
      displayName: user.displayName,
      pointsTotal: score.pointsTotal,
      breakdown: score.breakdown
    })
    .from(score)
    .innerJoin(session, eq(session.id, score.sessionId))
    .innerJoin(event, eq(event.id, session.eventId))
    .innerJoin(user, eq(user.id, score.userId))
    .innerJoin(leagueMember, and(eq(leagueMember.userId, score.userId), eq(leagueMember.leagueId, leagueId)))
    .where(eq(event.seasonYear, seasonYear))
    .orderBy(desc(session.scheduledStart))

  const bySession = new Map<number, SessionLeaderboardRow>()
  for (const r of rows) {
    let entry = bySession.get(r.sessionId)
    if (!entry) {
      entry = {
        sessionId: r.sessionId,
        sessionType: r.sessionType,
        eventRound: r.eventRound,
        eventName: r.eventName,
        scheduledStart: r.scheduledStart,
        members: []
      }
      bySession.set(r.sessionId, entry)
    }
    entry.members.push({
      userId: r.userId,
      displayName: r.displayName,
      pointsTotal: r.pointsTotal,
      breakdown: r.breakdown as ScoreBreakdown
    })
  }
  return Array.from(bySession.values())
}
