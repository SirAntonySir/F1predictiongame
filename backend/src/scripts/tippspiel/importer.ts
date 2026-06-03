import { hashPassword } from '../../auth/password.js'
import * as usersRepo from '../../repo/users.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as preseasonPicksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../repo/preseasonStandings.js'
import { getDb } from '../../db/client.js'
import { user as userTable, league as leagueTable } from '../../db/schema.js'
import { eq, sql } from 'drizzle-orm'
import type { ParsedSeason } from './types.js'
import { mapEventName, EVENTS_TO_SKIP } from './mappings.js'
import { SESSION_TYPE_BY_KIND } from './types.js'

const PASSWORD_PLAIN = 'tippspiel-test'
const LEAGUE_NAME = 'The Box'
const LEAGUE_JOIN_CODE = 'TIPP-2026'
const ANTON_EXCEL_NAME = 'Anton'

function emailFor(excelName: string): string {
  return `${excelName.toLowerCase()}@tippspiel.test`
}

export type ImportSummary = {
  userIdByExcelName: Map<string, string>
  leagueId: string
  predictionsUpserted: number
  preseasonPicksUpserted: number
  preseasonStandingsUpserted: number
  sessionsRescored: number
  skippedSessions: { reason: string; count: number }[]
}

export async function importParsedSeason(parsed: ParsedSeason): Promise<ImportSummary> {
  const db = getDb()
  const passwordHash = await hashPassword(PASSWORD_PLAIN)

  // 1. Upsert users (find-by-displayName so we don't duplicate when a real
  // email has been set on the row to replace the @tippspiel.test placeholder).
  const userIdByExcelName = new Map<string, string>()
  for (const player of parsed.players) {
    const existing = await db.select().from(userTable).where(eq(userTable.displayName, player.excelName)).limit(1)
    let id: string
    if (existing.length > 0) {
      id = existing[0]!.id
      // Leave email + passwordHash alone — they may have been customised after the initial import.
    } else {
      const created = await usersRepo.insertUser({
        email: emailFor(player.excelName),
        passwordHash,
        displayName: player.excelName,
      })
      id = created.id
    }
    userIdByExcelName.set(player.excelName, id)
  }

  const antonId = userIdByExcelName.get(ANTON_EXCEL_NAME)
  if (!antonId) throw new Error('Anton not found among parsed players — required as league owner')

  // 2. Upsert league (find-by-name)
  const existingLeague = await db.select().from(leagueTable).where(eq(leagueTable.name, LEAGUE_NAME)).limit(1)
  let leagueId: string
  if (existingLeague.length > 0) {
    leagueId = existingLeague[0]!.id
  } else {
    const antonsLeagues = await db.select().from(leagueTable).where(eq(leagueTable.ownerUserId, antonId)).limit(1)
    if (antonsLeagues.length > 0) {
      throw new Error(`cannot create "${LEAGUE_NAME}" — Anton already owns league "${antonsLeagues[0]!.name}". Delete it or use the existing one.`)
    }
    const created = await leaguesRepo.createLeagueWithOwner({ name: LEAGUE_NAME, ownerUserId: antonId, joinCode: LEAGUE_JOIN_CODE })
    leagueId = created.id
  }

  // 3. League membership for everyone (insert ignore)
  for (const [name, uid] of userIdByExcelName.entries()) {
    await db.execute(sql`
      INSERT INTO league_member (league_id, user_id)
      VALUES (${leagueId}::uuid, ${uid}::uuid)
      ON CONFLICT (league_id, user_id) DO NOTHING
    `)
    void name
  }

  // 4. Preseason standings + 5. preseason single picks
  let preseasonStandingsUpserted = 0
  let preseasonPicksUpserted = 0
  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    await preseasonStandingsRepo.replaceConstructorPicks(
      uid, parsed.seasonYear,
      player.preseasonStandings.constructors.map((c) => ({ position: c.position, entityId: c.constructorId }))
    )
    await preseasonStandingsRepo.replaceDriverPicks(
      uid, parsed.seasonYear,
      player.preseasonStandings.drivers.map((d) => ({ position: d.position, entityId: d.driverCode }))
    )
    preseasonStandingsUpserted += 2

    for (const [category, vals] of Object.entries(player.preseasonSingle)) {
      await preseasonPicksRepo.upsertPick(uid, parsed.seasonYear, category as any, {
        driverCode: vals!.driverCode,
        constructorId: vals!.constructorId
      })
      preseasonPicksUpserted += 1
    }
  }

  // 6. Per-race predictions
  const events = await eventsRepo.listForSeason(parsed.seasonYear)
  const eventIdByName = new Map(events.map((e) => [e.name, e.id]))
  const sessionsByEventId = new Map<number, { type: string; id: number }[]>()
  for (const ev of events) {
    const ss = await sessionsRepo.listForEvent(ev.id)
    sessionsByEventId.set(ev.id, ss.map((s) => ({ type: s.type, id: s.id })))
  }

  let predictionsUpserted = 0
  const skipReasons = new Map<string, number>()
  const bump = (r: string) => skipReasons.set(r, (skipReasons.get(r) ?? 0) + 1)

  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    for (const [excelEventName, picks] of Object.entries(player.racePicks)) {
      if (EVENTS_TO_SKIP.has(excelEventName)) continue
      const dbEventName = mapEventName(excelEventName)
      if (dbEventName === null) continue
      const eventId = eventIdByName.get(dbEventName)
      if (eventId === undefined) { bump(`event-not-in-db:${dbEventName}`); continue }
      const sessions = sessionsByEventId.get(eventId) ?? []
      const event = events.find((e) => e.id === eventId)!

      for (const kind of ['quali','sprintQuali','sprint','race'] as const) {
        const list = picks[kind]
        if (list.length === 0) continue
        const sessionType = SESSION_TYPE_BY_KIND[kind]
        if ((sessionType === 'sprint' || sessionType === 'sprint_quali') && !event.hasSprint) {
          throw new Error(`event ${dbEventName} has no sprint but Excel has ${kind} picks for player ${player.excelName}`)
        }
        const session = sessions.find((s) => s.type === sessionType)
        if (!session) { bump(`session-not-in-db:${dbEventName}:${sessionType}`); continue }
        await predictionsRepo.upsertPredictionWithPicks(uid, session.id, list)
        predictionsUpserted += 1
      }
    }
  }

  return {
    userIdByExcelName,
    leagueId,
    predictionsUpserted,
    preseasonPicksUpserted,
    preseasonStandingsUpserted,
    sessionsRescored: 0,
    skippedSessions: [...skipReasons.entries()].map(([reason, count]) => ({ reason, count }))
  }
}
