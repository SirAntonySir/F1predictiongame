import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as members from '../../repo/leagueMembers.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as eventsRepo from '../../repo/events.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as scoresRepo from '../../repo/scores.js'
import * as projectionSnapshotsRepo from '../../repo/preseasonProjectionSnapshots.js'
import { generateUniqueJoinCode } from '../../auth/joinCodes.js'
import { hashPassword, verifyPassword } from '../../auth/password.js'
import { getCurrentUser, registerAuthHook, requireLeagueMember, requireLeagueOwner } from '../auth-context.js'
import { resolveSeason } from '../season-query.js'

const createBody = z.object({
  name: z.string().trim().min(1).max(60),
  // Optional join-gate password. min(4) keeps it trivial-but-not-empty;
  // we don't need login-grade entropy since failed joins are rate-limited
  // by the existing UNAUTHORIZED responses. Pass null/omit to keep the
  // league open (code-only joins).
  password: z.string().min(4).max(100).optional()
})
const patchBody = z.object({
  name: z.string().trim().min(1).max(60).optional(),
  // password=null clears, password='abcd' sets, omitted leaves unchanged.
  password: z.string().min(4).max(100).nullable().optional()
})
const joinBody = z.object({
  joinCode: z.string().trim().min(1).max(20),
  password: z.string().min(1).max(100).optional()
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

async function leagueViewForCaller(leagueId: string, callerUserId: string) {
  const l = await leaguesRepo.findById(leagueId)
  if (!l) throw new ApiError('NOT_FOUND', 'League not found')
  const memberCount = await leaguesRepo.countMembers(l.id)
  const isOwner = l.ownerUserId === callerUserId
  return {
    id: l.id,
    name: l.name,
    ownerUserId: l.ownerUserId,
    memberCount,
    // The Flutter LeagueView model parses this as a required string. Keep
    // it on every league view (create / join / get / patch) so the client's
    // LeagueController.load() doesn't fail silently and stay null.
    role: isOwner ? 'owner' : 'member',
    // Surfaced on every view so the join screen knows whether to prompt
    // for a password before posting. Hash itself never leaves the repo.
    hasPassword: l.hasPassword,
    createdAt: l.createdAt,
    ...(isOwner ? { joinCode: l.joinCode } : {})
  }
}

export async function registerLeagueRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.post('/api/leagues', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(createBody, req.body)

    const existing = await leaguesRepo.listForUser(u.id)
    if (existing.some((l) => l.role === 'owner')) {
      throw new ApiError('CONFLICT', 'You already own a league')
    }

    const joinCode = await generateUniqueJoinCode(async (c) => {
      return (await leaguesRepo.findByJoinCode(c)) !== null
    })
    const passwordHash = body.password
      ? await hashPassword(body.password)
      : null
    const l = await leaguesRepo.createLeagueWithOwner({
      name: body.name,
      ownerUserId: u.id,
      joinCode,
      passwordHash
    })
    return { league: await leagueViewForCaller(l.id, u.id) }
  })

  app.get('/api/leagues/mine', async (req) => {
    const u = getCurrentUser(req)
    const list = await leaguesRepo.listForUser(u.id)
    return {
      leagues: list.map((l) => ({
        id: l.id,
        name: l.name,
        ownerUserId: l.ownerUserId,
        role: l.role,
        createdAt: l.createdAt,
        ...(l.role === 'owner' ? { joinCode: l.joinCode } : {})
      }))
    }
  })

  app.get<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    const u = getCurrentUser(req)
    const exists = await leaguesRepo.findById(req.params.id)
    if (!exists) throw new ApiError('NOT_FOUND', 'League not found')
    await requireLeagueMember(req, req.params.id)
    const league = await leagueViewForCaller(req.params.id, u.id)
    const list = await members.listByLeague(req.params.id)
    const ownerId = league.ownerUserId
    return {
      league,
      members: list.map((m) => ({
        userId: m.userId,
        displayName: m.displayName,
        role: m.userId === ownerId ? 'owner' : 'member',
        joinedAt: m.joinedAt
      }))
    }
  })

  app.patch<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    const u = getCurrentUser(req)
    await requireLeagueOwner(req, req.params.id)
    const body = parse(patchBody, req.body)
    if (body.name !== undefined) {
      await leaguesRepo.updateName(req.params.id, body.name)
    }
    if (body.password !== undefined) {
      // null clears the password (league becomes open again); a string
      // sets a fresh hash. Omitted = unchanged.
      const newHash = body.password === null
          ? null
          : await hashPassword(body.password)
      await leaguesRepo.updatePasswordHash(req.params.id, newHash)
    }
    return { league: await leagueViewForCaller(req.params.id, u.id) }
  })

  app.post<{ Params: { id: string } }>('/api/leagues/:id/regenerate-code', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    const code = await generateUniqueJoinCode(async (c) => (await leaguesRepo.findByJoinCode(c)) !== null)
    await leaguesRepo.updateJoinCode(req.params.id, code)
    return { joinCode: code }
  })

  app.delete<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    await leaguesRepo.deleteById(req.params.id)
    return { ok: true }
  })

  app.post('/api/leagues/join', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(joinBody, req.body)
    const code = body.joinCode.toUpperCase()
    const l = await leaguesRepo.findByJoinCodeWithSecret(code)
    if (!l) throw new ApiError('NOT_FOUND', 'Unknown join code')
    if (l.ownerUserId === u.id) throw new ApiError('CONFLICT', 'You already own this league')
    if (await members.isMember(l.id, u.id)) throw new ApiError('CONFLICT', 'Already a member')

    // Password gate: if the league has one, the joiner must supply a match.
    // FORBIDDEN (not UNAUTHORIZED) so the Flutter client doesn't treat
    // it as a logged-out signal and wipe the auth session — the caller
    // is properly authenticated, they just don't have the league key.
    if (l.passwordHash !== null) {
      if (!body.password) {
        throw new ApiError('FORBIDDEN', 'This league requires a password')
      }
      if (!(await verifyPassword(body.password, l.passwordHash))) {
        throw new ApiError('FORBIDDEN', 'Wrong league password')
      }
    }

    // Display-name uniqueness within the league. Two members can't share a
    // case-insensitive display name — otherwise leaderboards / gossip
    // become ambiguous. Conflict gives the joiner a chance to rename
    // themselves before retrying.
    const existing = await members.listByLeague(l.id)
    const myName = u.displayName.trim().toLowerCase()
    if (existing.some((m) => m.displayName.trim().toLowerCase() === myName)) {
      throw new ApiError(
        'CONFLICT',
        'Another member of this league already uses that display name — change yours first.'
      )
    }

    await members.add(l.id, u.id)
    return { league: await leagueViewForCaller(l.id, u.id) }
  })

  app.delete<{ Params: { id: string } }>('/api/leagues/:id/members/me', async (req) => {
    const u = getCurrentUser(req)
    const l = await leaguesRepo.findById(req.params.id)
    if (!l) throw new ApiError('NOT_FOUND', 'League not found')
    if (l.ownerUserId === u.id) throw new ApiError('CONFLICT', 'Owner must delete the league instead of leaving')
    if (!(await members.isMember(l.id, u.id))) throw new ApiError('NOT_FOUND', 'Not a member')
    await members.remove(l.id, u.id)
    return { ok: true }
  })

  app.delete<{ Params: { id: string; userId: string } }>('/api/leagues/:id/members/:userId', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    const l = await leaguesRepo.findById(req.params.id)
    if (l!.ownerUserId === req.params.userId) {
      throw new ApiError('BAD_REQUEST', 'Cannot kick the league owner')
    }
    await members.remove(req.params.id, req.params.userId)
    return { ok: true }
  })

  // League gossip for the most recent finished race: who topped the
  // weekend, who bottomed out, who forgot to pick, and which drivers were
  // the league's best/worst calls. All derived from the per-member
  // session scores + breakdowns we already store.
  app.get<{ Params: { id: string }; Querystring: { season?: string } }>(
    '/api/leagues/:id/gossip',
    async (req) => {
      const u = getCurrentUser(req)
      await requireLeagueMember(req, req.params.id)

      const season = await resolveSeason(req.query)

      // Find the most recent finished race in the season.
      const events = await eventsRepo.listForSeason(season)
      let lastRace: { id: number; scheduledStart: Date } | null = null
      let lastEvent: { round: number; name: string } | null = null
      for (const ev of events) {
        const sessions = await sessionsRepo.listForEvent(ev.id)
        for (const s of sessions) {
          if (s.type !== 'race' || s.status !== 'finished') continue
          if (lastRace === null || s.scheduledStart > lastRace.scheduledStart) {
            lastRace = { id: s.id, scheduledStart: s.scheduledStart }
            lastEvent = { round: ev.round, name: ev.name }
          }
        }
      }
      if (lastRace === null || lastEvent === null) return { lastRace: null, myProjection: null }

      // Caller's projection delta: compare the last two snapshots written by
      // the preseason rescorer. If only one snapshot exists, we can show
      // current but not the delta.
      const recent = await projectionSnapshotsRepo.listRecentForUser(
        u.id, season, 2
      )
      const myProjection = recent.length === 0
        ? null
        : {
            now: recent[0]!.projectedPoints,
            previous: recent.length >= 2 ? recent[1]!.projectedPoints : null,
            delta: recent.length >= 2
              ? recent[0]!.projectedPoints - recent[1]!.projectedPoints
              : null
          }

      const memberList = await members.listByLeague(req.params.id)
      const memberNameById = new Map(memberList.map((m) => [m.userId, m.displayName]))
      const memberIds = memberList.map((m) => m.userId)

      const preds = await predictionsRepo.listLeagueMemberPredictions(
        req.params.id,
        lastRace.id
      )
      const scoreRows = await scoresRepo.listForUsersAndSession(
        memberIds,
        lastRace.id
      )
      const scoreByUser = new Map(scoreRows.map((s) => [s.userId, s]))

      // Best / worst player: lowest+highest pointsTotal among scored members.
      const ranked = scoreRows
        .map((s) => ({
          userId: s.userId,
          displayName: memberNameById.get(s.userId) ?? '',
          points: s.pointsTotal
        }))
        .sort((a, b) => b.points - a.points)
      let bestPlayer: typeof ranked[number] | null = null
      let worstPlayers: typeof ranked = []
      if (ranked.length > 0) {
        const top = ranked[0]!.points
        const bottom = ranked[ranked.length - 1]!.points
        // Skip when everyone tied — nothing gossip-worthy.
        if (top > bottom) {
          bestPlayer = ranked[0]!
          worstPlayers = ranked.filter((r) => r.points === bottom)
        }
      }

      // No-shows: members who didn't submit a single pick.
      const predByUser = new Map(preds.map((p) => [p.userId, p]))
      const noShowPlayers = memberList
        .filter((m) => {
          const p = predByUser.get(m.userId)
          return !p || p.picks.length === 0
        })
        .map((m) => ({ userId: m.userId, displayName: m.displayName }))

      // Driver impact aggregation across the league's breakdowns.
      const gainedByDriver = new Map<string, number>()
      const missesByDriver = new Map<string, number>()
      for (const s of scoreRows) {
        const bd = s.breakdown as { perPosition?: Array<{ driverCode?: string | null; points?: number }> }
        const perPos = bd.perPosition ?? []
        for (const p of perPos) {
          const code = p.driverCode
          if (code == null) continue
          const pts = p.points ?? 0
          gainedByDriver.set(code, (gainedByDriver.get(code) ?? 0) + pts)
          if (pts === 0) {
            missesByDriver.set(code, (missesByDriver.get(code) ?? 0) + 1)
          }
        }
      }
      let driverGained: { driverCode: string; points: number } | null = null
      for (const [code, pts] of gainedByDriver) {
        if (pts > 0 && (driverGained === null || pts > driverGained.points)) {
          driverGained = { driverCode: code, points: pts }
        }
      }
      let driverCost: { driverCode: string; count: number } | null = null
      for (const [code, n] of missesByDriver) {
        if (n > 0 && (driverCost === null || n > driverCost.count)) {
          driverCost = { driverCode: code, count: n }
        }
      }
      // Avoid weird mention-only entries where caller's id is unused.
      void scoreByUser

      return {
        lastRace: {
          sessionId: lastRace.id,
          round: lastEvent.round,
          name: lastEvent.name
        },
        bestPlayer,
        worstPlayers,
        noShowPlayers,
        driverGained,
        driverCost,
        myProjection
      }
    }
  )

  // Every league member's picks + session score for one session. Gated by the
  // session's scheduledStart — predictions are hidden until kickoff so we
  // don't leak picks before lock. Used by the race-detail screen to render a
  // ticket per member below the official classification.
  app.get<{ Params: { id: string; sessionId: string } }>(
    '/api/leagues/:id/sessions/:sessionId/predictions',
    async (req) => {
      await requireLeagueMember(req, req.params.id)
      const sessionId = Number(req.params.sessionId)
      if (!Number.isFinite(sessionId)) {
        throw new ApiError('BAD_REQUEST', 'sessionId must be a number')
      }
      const s = await sessionsRepo.getById(sessionId)
      if (!s) throw new ApiError('NOT_FOUND', 'Session not found')

      if (s.scheduledStart.getTime() > Date.now()) {
        return { sessionLocked: false, predictions: [] }
      }

      const list = await predictionsRepo.listLeagueMemberPredictions(
        req.params.id,
        sessionId
      )
      return { sessionLocked: true, predictions: list }
    }
  )
}
